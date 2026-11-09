// fingers.cpp -- see fingers.h
#include "fingers.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "rack.h"
#include "reload.h"
#include "settings.h"
#include "shellclip.h"
#include "json_mini.h"
#include "zones.h"

#include <windows.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace vn::fingers {

using namespace joints;
using namespace vn::settings;

namespace {
// Village's left-hand finger joints (Andyalpa's re8_vr_hand_poser.lua LEFT_HAND_BONES)
const wchar_t* LEFT_FINGERS[] = {
    L"L_IndexF1", L"L_IndexF2", L"L_IndexF3", L"L_MiddleF1", L"L_MiddleF2", L"L_MiddleF3",
    L"L_RingF1", L"L_RingF2", L"L_RingF3", L"L_PinkyF1", L"L_PinkyF2", L"L_PinkyF3",
    L"L_Thumb1", L"L_Thumb2", L"L_Thumb3",
};
constexpr int N = sizeof(LEFT_FINGERS) / sizeof(LEFT_FINGERS[0]);

float g_open = 0.0f;        // 0 = as animated, 1 = FINGER_OPEN_AMOUNT of the way to rest
float g_last_t = -1.0f;
bool g_want = false;
bool g_poser = false;
const char* g_why = "";
MO* g_joint[N] = {};
Quat g_target[N] = {};
bool g_have[N] = {};
MO* g_tf = nullptr;

Quat nlerp(Quat a, Quat b, float u) {
    if (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w < 0.0f) b = {-b.x, -b.y, -b.z, -b.w};   // the short way round
    return qnorm({a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, a.z + (b.z - a.z) * u, a.w + (b.w - a.w) * u});
}

// ---- 2026-11-08 (Tefa, idea 37: "hand automatically changes to the game's original pose on the weapon the closer it gets to the
// middle of the activation zone - everything has to be hand tunable after"): the game's own left-hand hold per gun, cut from the
// finger takes by tools/make_finger_book.py: clips/<gun>_grip.csv (the idle's hold: the front grip, the pump, the grip handle) and
// clips/<gun>_grip_mag.csv (the grasp on the magazine). The free left hand eases into it as it nears the middle of that zone:
// nothing at START zone radii from the middle, all of it at FULL radii, times AMOUNT; tuned per gun in
// reframework/data/visceral_re8/grip_blend.json {"default": {"start": 1.6, "full": 0.35, "amount": 1}, "ri3046": {...}}
// (re-read once a second). A gun with no such pose (the idle's left hand hangs) keeps the opening hand as before.
struct GripPose { bool ok = false; Quat q[N]; bool have[N] = {}; };
std::map<std::string, GripPose> g_grip_cache;   // "<gun>_grip" / "<gun>_grip_mag" -> the pose (ok=false: no file)
const GripPose* g_pose = nullptr;               // the pose the hand is easing into now
float g_grip = 0.0f;                            // 0 = none of it, 1 = all of it
struct Blend { float start = GRIP_BLEND_START, full = GRIP_BLEND_FULL, amount = GRIP_BLEND_AMOUNT; };
std::map<std::string, Blend> g_blend;
std::filesystem::file_time_type g_blend_mtime{};
float g_blend_check = -10.0f;

std::filesystem::path data_path(const wchar_t* rel) {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    return std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / rel;
}
std::vector<std::string> split_csv(const std::string& line) {
    std::vector<std::string> out;
    std::stringstream ss(line);
    std::string c;
    while (std::getline(ss, c, ',')) {
        while (!c.empty() && (c.back() == '\r' || c.back() == ' ')) c.pop_back();
        out.push_back(c);
    }
    return out;
}
const GripPose& grip_pose(const std::string& name) {
    auto it = g_grip_cache.find(name);
    if (it != g_grip_cache.end()) return it->second;
    GripPose& p = g_grip_cache[name];
    const auto path = data_path(L"clips") / (std::wstring(name.begin(), name.end()) + L".csv");
    FILE* f = nullptr;
    if (_wfopen_s(&f, path.c_str(), L"rb") != 0 || f == nullptr) return p;
    std::string text;
    char buf[4096];
    size_t n;
    while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) text.append(buf, n);
    std::fclose(f);
    std::istringstream in(text);
    std::string head, row;
    if (!std::getline(in, head) || !std::getline(in, row)) return p;
    const auto hc = split_csv(head), rc = split_csv(row);
    int found = 0;
    for (int i = 0; i < N; ++i) {
        std::string jn;
        for (const wchar_t* w = LEFT_FINGERS[i]; *w; ++w) jn += (char)*w;
        int col = -1;
        for (size_t c = 0; c < hc.size(); ++c) if (hc[c] == jn + ".x") { col = (int)c; break; }
        if (col < 0 || col + 3 >= (int)rc.size()) continue;
        p.q[i] = qnorm(Quat{std::strtof(rc[col].c_str(), nullptr), std::strtof(rc[col + 1].c_str(), nullptr),
                            std::strtof(rc[col + 2].c_str(), nullptr), std::strtof(rc[col + 3].c_str(), nullptr)});
        p.have[i] = std::isfinite(p.q[i].w);
        if (p.have[i]) ++found;
    }
    p.ok = found > 0;
    LOGI("%s fingers: %s: the game's own left-hand hold %s (%d joints)", TAG, name.c_str(), p.ok ? "read" : "not found", found);
    return p;
}
void read_blend() {
    const float t = now_s();
    if (t - g_blend_check < 1.0f) return;
    g_blend_check = t;
    std::error_code ec;
    const auto path = data_path(L"grip_blend.json");
    const auto mt = std::filesystem::last_write_time(path, ec);
    if (ec || mt == g_blend_mtime) return;
    json::Value v;
    if (!json::load_file(path.wstring(), v) || v.kind != json::Value::OBJ) return;
    g_blend_mtime = mt;
    g_blend.clear();
    for (const auto& [gun, e] : v.obj) {
        if (e.kind != json::Value::OBJ) continue;
        Blend b;
        auto num = [&](const char* k, float d) { const auto* x = e.get(k); return x != nullptr && x->kind == json::Value::NUM ? (float)x->n : d; };
        b.start = num("start", b.start); b.full = num("full", b.full); b.amount = num("amount", b.amount);
        g_blend[gun] = b;
    }
    LOGI("%s fingers: grip_blend.json read (%d entries)", TAG, (int)g_blend.size());
}
Blend blend_for(const std::string& gun) {
    auto it = g_blend.find(gun);
    if (it != g_blend.end()) return it->second;
    it = g_blend.find("default");
    return it != g_blend.end() ? it->second : Blend{};
}
int g_area = 0;
} // namespace

int left_area() { return g_area; }

void frame() {
    const float t = now_s();
    const float dt = g_last_t < 0 ? 0.0f : std::fmin(0.1f, t - g_last_t);
    g_last_t = t;
    const auto& s = player::now();
    const bool play = FINGER_OPEN_ON && bridge::live() && bridge::flag(bridge::S_CAN_USE_HANDS) && !bridge::flag(bridge::S_CUTSCENE);
    bool free_hand = !bridge::held(bridge::S_LGRIP) && !bridge::flag(bridge::S_GRIPPING_WEAPON) && !rack::active() &&
                     !reload::mag_in_hand() && !reload::round_in_hand() && !shellclip::playing_left();
    // 2026-11-09 (Tefa, screenshot 01:41: "at the end of the slide rack, fingers still automatically open"): the hand comes off the
    // slide right inside the slide's zone, where an empty hand opens toward the part. After letting go of a part the fingers stay as
    // they are (no opening, no easing into the game's hold) until the left controller has left the grab areas once
    // b099 (2026-11-09, Tefa: "can the hand open up straight after letting go of LG on the slide"): with the ready / free poses on,
    // the area is told to Hand Poser (pairs.cpp) and the fingers are not held shut after a part
    {
        const bool area = free_hand && (reload::in_pouch() || reload::hand_near_mag() || (s.gun != nullptr && rack::left_near_gun()));
        g_area = !play || !free_hand ? 0 : area ? 1 : 2;
    }
    static bool was_on_part = false, after_part = false;
    const bool on_part = rack::active();
    if (was_on_part && !on_part) after_part = true;
    was_on_part = on_part;
    if (after_part && !rack::left_near_gun()) after_part = false;
    if (after_part && !READY_POSES_ON) free_hand = false;
    // 2026-10-25 (Tefa, screenshots: the hand "teleport alternates between hand poses" near the gun): the open hand stepped on
    // at the zone's edge and fought Hand Poser, which holds the same joints. Now it ramps with the distance to the gun, and
    // stands down entirely while a poser holds any finger
    g_poser = bridge::view(bridge::S_POSER_HELD) > 0.5f;
    float aim = 0.0f;
    // 2026-11-08 (idea 37): near the middle of a grab zone whose game hold we have, the hand eases into that hold instead of opening
    float grip_aim = 0.0f;
    const GripPose* pose = nullptr;
    if (GRIP_BLEND_ON && play && free_hand && !g_poser && s.gun != nullptr && !reload::in_pouch()) {
        read_blend();
        const std::string gun = s.weapon_id.substr(0, s.weapon_id.find('_'));
        Vec3 lp;
        zones::Key key = zones::MAG;
        float q = 99.0f;
        if (!gun.empty() && bridge::room_to_world(bridge::hand_pos(bridge::LEFT), lp) && zones::nearest_grab(lp, key, q)) {
            const GripPose& gp = grip_pose(gun + (key == zones::MAG ? "_grip_mag" : "_grip"));
            const Blend b = blend_for(gun);
            if (gp.ok && b.start > b.full) {
                grip_aim = std::fmax(0.0f, std::fmin(1.0f, (b.start - q) / (b.start - b.full))) * std::fmax(0.0f, std::fmin(1.0f, b.amount));
                if (grip_aim > 0.0f) pose = &gp;
            }
        }
    }
    if (grip_aim > 0.0f && pose != g_pose) {
        if (g_pose == nullptr || g_grip <= 0.001f) g_pose = pose;   // a new hold only from none (a change mid-way would jump)
        else grip_aim = 0.0f;                                    // ease out of the old one first
    }
    if (play && free_hand && !g_poser && grip_aim <= 0.0f) {
        if (reload::in_pouch()) { aim = 1.0f; g_why = "pouch"; }
        // 2026-11-05 (Tefa, in the headset: "hand doesn't widen at the mag activation area ... but LG works there"): the seated
        // magazine's zone opens the hand too (the same real-hand test the LG grab uses, reload.cpp hand_near_mag)
        else if (reload::hand_near_mag()) { aim = 1.0f; g_why = "magazine"; }
        else if (s.gun != nullptr) { aim = rack::left_gun_closeness(); if (aim > 0.0f) g_why = "gun"; }
    }
    const bool want = aim > 0.001f;
    if (want != g_want) { g_want = want; LOGI("%s fingers: %s", TAG, want ? (std::string("opening (") + g_why + ")").c_str() : (g_poser ? "standing down: a hand poser holds the fingers" : "back to the game's pose")); }
    const float step = FINGER_OPEN_SEC > 0.0f ? dt / FINGER_OPEN_SEC : 1.0f;
    g_open = g_open < aim ? std::fmin(aim, g_open + step) : std::fmax(aim, g_open - step);
    const float gstep = GRIP_BLEND_SEC > 0.0f ? dt / GRIP_BLEND_SEC : 1.0f;   // follows the distance, rate-limited (no jumps)
    const bool grip_was = g_grip > 0.001f;
    g_grip = g_grip < grip_aim ? std::fmin(grip_aim, g_grip + gstep) : std::fmax(grip_aim, g_grip - gstep);
    if ((g_grip > 0.001f) != grip_was) LOGI("%s fingers: %s", TAG, g_grip > 0.001f ? "easing into the game's own hold (near the zone's middle)" : "out of the game's hold");
    if (g_grip <= 0.001f && grip_aim <= 0.0f) g_pose = nullptr;
    if (s.tf != g_tf) { g_tf = s.tf; for (auto& j : g_joint) j = nullptr; }
}

// 2026-10-25 01:25 (Tefa: near the pump "the hand smoothly rotates to the pose of what it is like when it actually is gripping
// on the gun ... it gets stuck after taking the hand off"): the skeleton's rest pose (BaseLocalRotation) is a relaxed CURL in
// Village, so blending toward it closed the hand; and nothing else re-poses the finger joints, so whatever was last written
// stayed. Now: "open" is the identity local rotation (each finger bone straight along its parent); the pose found at the
// start of an episode is kept and written back exactly when the episode ends; nothing is written outside an episode
bool g_episode = false;
Quat g_found[N] = {};
void render_point() {
    for (auto& h : g_have) h = false;
    if (g_tf == nullptr || g_poser) { if (g_episode) { g_episode = false; } return; }
    if (g_open <= 0.001f && (g_grip <= 0.001f || g_pose == nullptr)) {
        if (g_episode) {   // the episode ends: the hand as it was found, written once more, then left alone
            g_episode = false;
            for (int i = 0; i < N; ++i) if (g_joint[i] != nullptr) { g_target[i] = g_found[i]; g_have[i] = true; set_any(JOINT, g_joint[i], "set_LocalRotation", &g_target[i]); }
        }
        return;
    }
    const float u = ease(g_open) * FINGER_OPEN_AMOUNT;
    const Quat open{0, 0, 0, 1};
    for (int i = 0; i < N; ++i) {
        if (g_joint[i] == nullptr) g_joint[i] = joint_by_name(g_tf, LEFT_FINGERS[i]);
        MO* j = g_joint[i];
        if (j == nullptr) continue;
        if (!g_episode) {   // the pose as found, kept for the whole episode (later reads would see our own writes)
            Quat q;
            if (!get_q(JOINT, j, "get_LocalRotation", q)) continue;
            g_found[i] = qnorm(q);
        }
        g_target[i] = nlerp(g_found[i], open, u);
        if (g_pose != nullptr && g_pose->have[i] && g_grip > 0.001f) g_target[i] = nlerp(g_target[i], g_pose->q[i], ease(g_grip));   // 2026-11-08
        g_have[i] = true;
        set_any(JOINT, j, "set_LocalRotation", &g_target[i]);
    }
    g_episode = true;
}

bool busy() { return g_open > 0.001f || g_grip > 0.001f || g_episode; }

void begin_render() {
    if (g_poser) return;
    for (int i = 0; i < N; ++i)
        if (g_have[i] && g_joint[i] != nullptr) set_any(JOINT, g_joint[i], "set_LocalRotation", &g_target[i]);
}

} // namespace vn::fingers
