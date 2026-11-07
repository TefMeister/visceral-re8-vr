// timings.cpp -- see timings.h
#include "timings.h"
#include "common.h"
#include "joints.h"
#include "json_mini.h"
#include "settings.h"

#include <windows.h>

#include <cstdio>
#include <filesystem>
#include <string>

namespace vn::timings {

using namespace vn::settings;

namespace {
struct Row { const char* key; float dflt; const char* unit; const char* words; };
// the order is the enum's (timings.h); the words are what the window prints beside the slider
const Row ROWS[KEY_COUNT] = {
    {"cover_swing_s", LID_SWING_SEC, "s", "the loading cover swings open or shut"},
    {"thumb_lift_s", GATE_LIFT_SEC, "s", "the right thumb lifts over the hammer before the cover opens (and back)"},
    {"hammer_press_s", GATE_PRESS_SEC, "s", "LT presses the hammer down and back up"},
    {"hammer_press_cm", GATE_PRESS_M * 100.0f, "cm", "how far the palm goes down in that press"},
    {"drum_turn_s", GATE_CYL_TURN_SEC, "s", "the drum turns one chamber"},
    {"hand_glide_s", GATE_GLIDE_SEC, "s", "a hand glides onto its place on the gun"},
    {"right_return_s", GATE_RETURN_SEC, "s", "the right hand goes back onto the grip before the thumb shuts the cover"},
    {"stay_glide_s", GATE_STAY_GLIDE_SEC, "s", "the left hand leaves the drum for its hold after loading"},
    {"handover_s", RIGHT_RACK_HANDOVER_SEC, "s", "the gun eases back onto the right controller"},
    {"drop_s", RIGHT_RACK_DROP_SEC, "s", "LG let go mid-way: the gun back onto the right hand"},
    {"thumb_flick_s", GATE_FLICK_SEC, "s", "the right thumb's flick at the cover"},
    {"clip_blend_s", SHELLCLIP_BLEND_S, "s", "a finger movement blends in from, and out to, the hand's pose"},
    {"case_at_open_s", DRUM_CASE_AT_OPEN_S, "s", "the case at the cover comes out this long after the cover starts to open"},
    {"case_after_turn_s", DRUM_CASE_AFTER_TURN_S, "s", "the case starts out this long after the drum's turn ends"},
    {"case_slide_s", DRUM_CASE_SLIDE_S, "s", "the case slides out of the chamber, back through the cover"},
    {"case_fall_s", DRUM_CASE_FALL_SEC, "s", "the case falls, then it is gone"},
    {"insert_reach_s", DRUM_INSERT_REACH_S, "s", "the round travels from the hand to just behind the cover"},
    {"insert_push_s", DRUM_INSERT_PUSH_S, "s", "then it is pushed in"},
    {"held_follow_s", GATE_HELD_FOLLOW_SEC, "s", "the gun in the left hand follows it with this smoothing (0 = raw)"},
    {"load_ease_s", DRUM_LOAD_EASE_SEC, "s", "the hand eases between the drum and the loading place"},
};
float g_val[KEY_COUNT];
bool g_set[KEY_COUNT];
bool g_init = false;
std::filesystem::file_time_type g_mtime{};
bool g_had_file = false;
float g_check_t = -10.0f;
bool g_known_written = false;

std::filesystem::path dir() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    return std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8";
}

void init() {
    if (g_init) return;
    g_init = true;
    for (int i = 0; i < KEY_COUNT; ++i) { g_val[i] = ROWS[i].dflt; g_set[i] = false; }
}

void write_known() {
    std::error_code ec;
    std::filesystem::create_directories(dir(), ec);
    FILE* f = _wfopen((dir() / "timings_known.json").wstring().c_str(), L"wb");
    if (f == nullptr) return;
    std::fputs("{\"items\":[", f);
    for (int i = 0; i < KEY_COUNT; ++i)
        std::fprintf(f, "%s\n  {\"key\":\"%s\",\"default\":%.4f,\"value\":%.4f,\"set\":%s,\"unit\":\"%s\",\"words\":\"%s\"}",
                     i == 0 ? "" : ",", ROWS[i].key, ROWS[i].dflt, g_val[i], g_set[i] ? "true" : "false", ROWS[i].unit, ROWS[i].words);
    std::fputs("\n]}\n", f);
    std::fclose(f);
    g_known_written = true;
}

void read_file() {
    const auto p = dir() / "timings.json";
    std::error_code ec;
    const bool exists = std::filesystem::exists(p, ec);
    const auto mt = exists ? std::filesystem::last_write_time(p, ec) : std::filesystem::file_time_type{};
    if (exists == g_had_file && (!exists || mt == g_mtime)) return;
    json::Value v;
    if (exists && !json::load_file(p.wstring(), v)) return;   // caught mid-write: the next check reads it
    g_had_file = exists;
    g_mtime = mt;
    int n = 0;
    for (int i = 0; i < KEY_COUNT; ++i) {
        const auto* x = exists ? v.get(ROWS[i].key) : nullptr;
        const bool set = x != nullptr && x->kind == json::Value::NUM;
        const float nv = set ? (float)x->n : ROWS[i].dflt;
        if (set != g_set[i] || nv != g_val[i]) {
            LOGI("%s timings: %s = %.3f %s%s (default %.3f)", TAG, ROWS[i].key, nv, ROWS[i].unit, set ? "" : " (back to the default)", ROWS[i].dflt);
            ++n;
        }
        g_val[i] = nv;
        g_set[i] = set;
    }
    LOGI("%s timings: timings.json %s: %d change(s)", TAG, exists ? "read" : "gone", n);
    write_known();
}
} // namespace

float v(Key k) { init(); return (k >= 0 && k < KEY_COUNT) ? g_val[k] : 0.0f; }
bool has(Key k) { init(); return (k >= 0 && k < KEY_COUNT) && g_set[k]; }

void frame() {
    init();
    const float t = joints::now_s();
    if (t - g_check_t < 0.5f) return;
    g_check_t = t;
    read_file();
    if (!g_known_written) write_known();
}

} // namespace vn::timings
