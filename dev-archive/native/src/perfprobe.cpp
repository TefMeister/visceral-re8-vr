// perfprobe.cpp -- see perfprobe.h. (2026-11-02)
#include "perfprobe.h"

#include <windows.h>
#include <dxgi1_4.h>
#include <psapi.h>
#include <tlhelp32.h>

#include <atomic>
#include <chrono>
#include <cstring>
#include <cstdio>
#include <ctime>
#include <filesystem>
#include <thread>

#include "common.h"
#include "settings.h"

namespace vn::perfprobe {
namespace {

using namespace vn::settings;

// one rate (game frames or presents): written on the game / render thread, read and reset by the probe thread
struct Rate {
    std::atomic<int64_t> last{0};      // QPC of the previous tick
    std::atomic<uint32_t> count{0};
    std::atomic<uint32_t> max_gap_us{0};
    std::atomic<uint32_t> hitches{0};
};
Rate g_frame, g_present;
double g_qpc_per_us = 0.0;
HANDLE g_file = INVALID_HANDLE_VALUE;
IDXGIAdapter3* g_adapter = nullptr;

void tick(Rate& r) {
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    const int64_t prev = r.last.exchange(now.QuadPart);
    r.count.fetch_add(1, std::memory_order_relaxed);
    if (prev == 0 || g_qpc_per_us <= 0.0) return;
    const auto gap = static_cast<uint32_t>((now.QuadPart - prev) / g_qpc_per_us);
    if (gap > PERF_HITCH_MS * 1000) r.hitches.fetch_add(1, std::memory_order_relaxed);
    uint32_t m = r.max_gap_us.load(std::memory_order_relaxed);
    while (gap > m && !r.max_gap_us.compare_exchange_weak(m, gap)) {}
}

struct Taken { uint32_t count, max_us, hitches; };
Taken take(Rate& r) {
    return {r.count.exchange(0), r.max_gap_us.exchange(0), r.hitches.exchange(0)};
}

void write_line(const char* s) {
    if (g_file == INVALID_HANDLE_VALUE) return;
    DWORD n = 0;
    WriteFile(g_file, s, static_cast<DWORD>(std::strlen(s)), &n, nullptr);
    FlushFileBuffers(g_file);   // on the disk now: a blue screen keeps everything up to this line
}

// the card with the most memory of its own is the one the game draws on (this PC: the NVIDIA card, not the Intel one)
void pick_adapter() {
    IDXGIFactory1* f = nullptr;
    if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&f)))) return;
    SIZE_T best = 0;
    IDXGIAdapter1* a = nullptr;
    for (UINT i = 0; f->EnumAdapters1(i, &a) != DXGI_ERROR_NOT_FOUND; ++i) {
        DXGI_ADAPTER_DESC1 d{};
        a->GetDesc1(&d);
        IDXGIAdapter3* a3 = nullptr;
        if (d.DedicatedVideoMemory > best && SUCCEEDED(a->QueryInterface(__uuidof(IDXGIAdapter3), reinterpret_cast<void**>(&a3)))) {
            if (g_adapter != nullptr) g_adapter->Release();
            g_adapter = a3;
            best = d.DedicatedVideoMemory;
        }
        a->Release();
    }
    f->Release();
}

DWORD thread_count() {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snap == INVALID_HANDLE_VALUE) return 0;
    const DWORD me = GetCurrentProcessId();
    DWORD n = 0;
    THREADENTRY32 te{sizeof(te)};
    for (BOOL ok = Thread32First(snap, &te); ok; ok = Thread32Next(snap, &te)) n += (te.th32OwnerProcessID == me);
    CloseHandle(snap);
    return n;
}

uint64_t ft64(FILETIME f) { return (static_cast<uint64_t>(f.dwHighDateTime) << 32) | f.dwLowDateTime; }

void run() {
    SYSTEM_INFO si{};
    GetSystemInfo(&si);
    const double cpus = si.dwNumberOfProcessors > 0 ? si.dwNumberOfProcessors : 1;
    const ULONGLONG t0 = GetTickCount64();
    ULONGLONG t_prev = t0;
    uint64_t cpu_prev = 0;
    DWORD faults_prev = 0;
    bool first = true;
    constexpr double MB = 1024.0 * 1024.0;
    for (;;) {
        std::this_thread::sleep_for(std::chrono::milliseconds(PERF_PERIOD_S * 1000));
        const ULONGLONG t = GetTickCount64();
        const double dt = (t - t_prev) / 1000.0;
        t_prev = t;
        const Taken fr = take(g_frame), pr = take(g_present);

        FILETIME c, e, k, u;
        GetProcessTimes(GetCurrentProcess(), &c, &e, &k, &u);
        const uint64_t cpu = ft64(k) + ft64(u);   // 100 ns units, all threads
        const double cpu_pct = first ? 0.0 : (cpu - cpu_prev) / 1e7 / dt / cpus * 100.0;
        cpu_prev = cpu;

        PROCESS_MEMORY_COUNTERS_EX pm{};
        GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&pm), sizeof(pm));
        const double faults = first ? 0.0 : (pm.PageFaultCount - faults_prev) / dt;
        faults_prev = pm.PageFaultCount;
        DWORD handles = 0;
        GetProcessHandleCount(GetCurrentProcess(), &handles);

        DXGI_QUERY_VIDEO_MEMORY_INFO vm{};
        if (g_adapter != nullptr) g_adapter->QueryVideoMemoryInfo(0, DXGI_MEMORY_SEGMENT_GROUP_LOCAL, &vm);
        MEMORYSTATUSEX ms{sizeof(ms)};
        GlobalMemoryStatusEx(&ms);

        std::time_t now = std::time(nullptr);
        std::tm tm{};
        localtime_s(&tm, &now);
        char stamp[16]{};
        std::strftime(stamp, sizeof(stamp), "%H:%M:%S", &tm);
        char line[512];
        std::snprintf(line, sizeof(line),
            "%s,%llu,%.1f,%.1f,%u,%.1f,%.1f,%u,%.1f,%.0f,%.0f,%.0f,%lu,%lu,%.0f,%.0f,%lu,%.0f,%.0f\r\n",
            stamp, (t - t0) / 1000, fr.count / dt, fr.max_us / 1000.0, fr.hitches, pr.count / dt, pr.max_us / 1000.0,
            pr.hitches, cpu_pct, pm.WorkingSetSize / MB, pm.PrivateUsage / MB, faults, handles, thread_count(),
            vm.CurrentUsage / MB, vm.Budget / MB, ms.dwMemoryLoad, ms.ullAvailPhys / MB,
            (ms.ullTotalPageFile - ms.ullAvailPageFile) / MB);
        write_line(line);
        first = false;
    }
}

} // namespace

void frame() { tick(g_frame); }
void present() { tick(g_present); }

void start() {
    static std::atomic<bool> started{false};
    if (started.exchange(true)) return;
    LARGE_INTEGER f;
    QueryPerformanceFrequency(&f);
    g_qpc_per_us = f.QuadPart / 1e6;

    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto dir = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "perf";
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    std::time_t t = std::time(nullptr);
    std::tm tm{};
    localtime_s(&tm, &t);
    wchar_t name[64]{};
    wcsftime(name, 64, L"perf-%Y-%m-%d-%H%M%S.csv", &tm);
    g_file = CreateFileW((dir / name).c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS,
                         FILE_ATTRIBUTE_NORMAL, nullptr);
    if (g_file == INVALID_HANDLE_VALUE) { LOGI("%s perfprobe: could not open its file, not recording", TAG); return; }
    write_line("time,uptime_s,game_fps,game_max_ms,game_stutters,present_fps,present_max_ms,present_stutters,"
               "cpu_pct,ram_mb,private_mb,pagefaults_s,handles,threads,vram_mb,vram_budget_mb,pc_mem_load_pct,"
               "pc_free_mb,pc_commit_mb\r\n");
    pick_adapter();
    LOGI("%s perfprobe: recording every %d s to reframework/data/visceral_re8/perf/%ls (video memory %s)", TAG,
         PERF_PERIOD_S, name, g_adapter != nullptr ? "found" : "NOT found");
    std::thread(run).detach();
}

} // namespace vn::perfprobe
