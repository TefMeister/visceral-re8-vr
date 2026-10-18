// ghosthand.cpp -- see ghosthand.h. The writer is visceral-re2-vr's (same line format); the samples are Village's.
#include "ghosthand.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "rack.h"
#include "reload.h"
#include "settings.h"

#include <windows.h>

#include <chrono>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <string>

namespace vn::ghosthand {

using namespace joints;
using namespace vn::settings;

namespace {
FILE* g_f = nullptr;
std::string g_buf;
std::chrono::steady_clock::time_point g_t0, g_last_flush;
bool g_need_sent = false;

long long now_us() { return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - g_t0).count(); }

void flush() {
    if (g_f != nullptr && !g_buf.empty()) { std::fwrite(g_buf.data(), 1, g_buf.size(), g_f); std::fflush(g_f); g_buf.clear(); }
    g_last_flush = std::chrono::steady_clock::now();
}

void put(const char* fmt, ...) {
    if (g_f == nullptr) return;
    char line[256];
    va_list ap;
    va_start(ap, fmt);
    std::vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    g_buf += line;
    if (g_buf.size() > 64 * 1024) flush();
}

void vr_on() {
    if (g_f != nullptr) return;
    char base[MAX_PATH]{};
    const DWORD got = GetEnvironmentVariableA("LOCALAPPDATA", base, MAX_PATH);
    std::string dir = std::string(got > 0 && got < MAX_PATH ? base : ".") + "\\BeG0nE";
    CreateDirectoryA(dir.c_str(), nullptr);
    dir += "\\ghost-hand";
    CreateDirectoryA(dir.c_str(), nullptr);
    char stamp[32];
    const std::time_t t = std::time(nullptr);
    std::tm tm{};
    localtime_s(&tm, &t);
    std::strftime(stamp, sizeof stamp, "%Y%m%d-%H%M%S", &tm);
    const std::string path = dir + "\\visceral-re8-vr_" + stamp + ".ghl";
    if (fopen_s(&g_f, path.c_str(), "wb") != 0) { g_f = nullptr; LOGW("%s ghost hand: could not open %s", TAG, path.c_str()); return; }
    g_t0 = std::chrono::steady_clock::now();
    g_need_sent = false;
    // pid: the Lanes rider records this program's window while the log grows
    put("#ghosthand 1 game=visceral-re8-vr runtime=openxr pid=%lu\n", GetCurrentProcessId());
    flush();
    LOGI("%s ghost hand: recording to %s", TAG, path.c_str());
}

void vr_off() {
    if (g_f == nullptr) return;
    put("#end\n");
    flush();
    std::fclose(g_f);
    g_f = nullptr;
    LOGI("%s ghost hand: recording closed", TAG);
}

void real(const char* side, Vec3 p) {
    const bool tracked = bridge::has(p.x) && !(p.x == 0.0f && p.y == 0.0f && p.z == 0.0f);
    put("%lld R %s %d %.4f %.4f %.4f\n", now_us(), side, tracked ? 1 : 0, tracked ? p.x : 0.0f, tracked ? p.y : 0.0f, tracked ? p.z : 0.0f);
}

void world_line(const char* kind, const char* name, MO* joint) {   // a game-world joint, carried into the room
    Vec3 p, r;
    if (joint != nullptr && get_v3(JOINT, joint, "get_Position", p) && bridge::world_to_room(p, r))
        put("%lld %s %s %.4f %.4f %.4f\n", now_us(), kind, name, r.x, r.y, r.z);
}
} // namespace

void event(const char* gesture, const char* what) { put("%lld E %s %s\n", now_us(), gesture, what); }
void value(const char* name, float v) { put("%lld V %s %.5f\n", now_us(), name, v); }

void render_point() {
    if (!GHOST_HAND_ON) return;
    if (!bridge::live()) { vr_off(); return; }
    vr_on();
    if (g_f == nullptr) return;
    if (!g_need_sent) { value("rack_need", RACK_PULL_M); value("mag_need", DOCK_ITEM_M); g_need_sent = true; }

    real("L", bridge::hand_pos(bridge::LEFT));
    real("R", bridge::hand_pos(bridge::RIGHT));
    const auto& s = player::now();
    world_line("G", "L", joint_by_name(s.tf, L"L_Hand"));
    world_line("G", "R", joint_by_name(s.tf, L"R_Hand"));
    world_line("P", rack::part_name(), static_cast<MO*>(rack::slide_joint()));
    world_line("P", "magazine", joint_by_name(s.weapon_tf, L"Magazine"));
    value("rack", rack::travel());
    value("hand_on", rack::active() ? 1.0f : 0.0f);
    value("loaded", static_cast<float>(player::loaded()));
    value("mag_in_hand", reload::mag_in_hand() ? 1.0f : 0.0f);
    value("round_in_hand", reload::round_in_hand() ? 1.0f : 0.0f);
    put("%lld B LG %d\n", now_us(), bridge::held(bridge::S_LGRIP) ? 1 : 0);
    put("%lld B LT %d\n", now_us(), bridge::held(bridge::S_LTRIG) ? 1 : 0);
    put("%lld B RB %d\n", now_us(), bridge::held(bridge::S_RB) ? 1 : 0);
    put("%lld F\n", now_us());
    if (std::chrono::steady_clock::now() - g_last_flush > std::chrono::seconds(1)) flush();
}

void shutdown() { vr_off(); }

} // namespace vn::ghosthand
