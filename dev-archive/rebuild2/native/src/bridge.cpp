// bridge.cpp -- see bridge.h
#include "bridge.h"

#include "base.h"
#include "paths.h"

#include <cstdlib>
#include <fstream>
#include <string>

namespace vr8::bridge {

namespace {
constexpr int ARRAY_DATA_AT = 0x20;        // a managed array's first element (b178's bridge, RE Engine, measured there)
constexpr float RETRY_S = 1.0f;            // how often the file is read while not attached
constexpr int STALE_FRAMES = 120;          // the counter stood still this long: the scripts were reset
constexpr const char* ARRAY_TYPE = "System.Single[]";

const float* g_data = nullptr;             // the array's floats; nullptr = not attached
MO* g_array = nullptr;
float g_last_try = -RETRY_S;
float g_last_counter = -1.0f;
int g_stale = 0;
bool g_told_waiting = false;

void let_go(const char* why) {
    if (g_data != nullptr) LOGI("%s bridge: let go (%s)", TAG, why);
    g_data = nullptr;
    g_array = nullptr;
    g_last_counter = -1.0f;
    g_stale = 0;
}

void try_attach() {
    // the script writes the file with REFramework's json.dump_file: {"a_address":"<digits>","b_sentinel":<digits>}.
    // The two numbers are the file's first two runs of digits (the key names hold none), so no JSON reader is needed.
    std::ifstream f(paths::data(L"bridge.txt"));
    std::string text((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    unsigned long long numbers[2] = {0, 0};
    int found = 0;
    for (size_t i = 0; i < text.size() && found < 2; ++i) {
        if (text[i] < '0' || text[i] > '9') continue;
        char* end = nullptr;
        numbers[found++] = std::strtoull(text.c_str() + i, &end, 10);
        i = (size_t)(end - text.c_str());
    }
    const unsigned long long address = numbers[0];
    const double sentinel = (double)numbers[1];
    if (found < 2 || address == 0) {
        if (!g_told_waiting) { g_told_waiting = true; LOGI("%s bridge: waiting for visceral_re8_bridge.lua", TAG); }
        return;
    }
    auto* candidate = (MO*)(uintptr_t)address;
    if (!is_managed(candidate) || type_name(candidate) != ARRAY_TYPE) return;   // a file from an earlier run
    const auto* data = (const float*)((const char*)candidate + ARRAY_DATA_AT);
    if (data[S_SENTINEL] != (float)sentinel) return;
    g_array = candidate;
    g_data = data;
    g_last_counter = -1.0f;
    g_stale = 0;
    LOGI("%s bridge: attached", TAG);
}
} // namespace

void frame() {
    if (g_data == nullptr) {
        const float now = now_s();
        if (now - g_last_try < RETRY_S) return;
        g_last_try = now;
        try_attach();
        return;
    }
    if (!is_managed(g_array)) { let_go("the array is gone"); return; }
    const float counter = g_data[S_FRAME];
    if (counter != g_last_counter) { g_last_counter = counter; g_stale = 0; return; }
    if (++g_stale > STALE_FRAMES) let_go("the frame counter stopped");
}

bool live() { return g_data != nullptr && g_stale <= STALE_FRAMES / 4; }

float read(Slot slot) { return live() ? g_data[slot] : 0.0f; }

} // namespace vr8::bridge
