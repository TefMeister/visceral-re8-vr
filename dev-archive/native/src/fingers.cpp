// fingers.cpp -- see fingers.h
#include "fingers.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "rack.h"
#include "reload.h"
#include "settings.h"

#include <cmath>

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
} // namespace

void frame() {
    const float t = now_s();
    const float dt = g_last_t < 0 ? 0.0f : std::fmin(0.1f, t - g_last_t);
    g_last_t = t;
    const auto& s = player::now();
    const bool play = FINGER_OPEN_ON && bridge::live() && bridge::flag(bridge::S_CAN_USE_HANDS) && !bridge::flag(bridge::S_CUTSCENE);
    const bool free_hand = !bridge::held(bridge::S_LGRIP) && !bridge::flag(bridge::S_GRIPPING_WEAPON) && !rack::active() &&
                           !reload::mag_in_hand() && !reload::round_in_hand();
    // 2026-10-25 (Tefa, screenshots: the hand "teleport alternates between hand poses" near the gun): the open hand stepped on
    // at the zone's edge and fought Hand Poser, which holds the same joints. Now it ramps with the distance to the gun, and
    // stands down entirely while a poser holds any finger
    g_poser = bridge::view(bridge::S_POSER_HELD) > 0.5f;
    float aim = 0.0f;
    if (play && free_hand && !g_poser) {
        if (reload::in_pouch()) { aim = 1.0f; g_why = "pouch"; }
        else if (s.gun != nullptr) { aim = rack::left_gun_closeness(); if (aim > 0.0f) g_why = "gun"; }
    }
    const bool want = aim > 0.001f;
    if (want != g_want) { g_want = want; LOGI("%s fingers: %s", TAG, want ? (std::string("opening (") + g_why + ")").c_str() : (g_poser ? "standing down: a hand poser holds the fingers" : "back to the game's pose")); }
    const float step = FINGER_OPEN_SEC > 0.0f ? dt / FINGER_OPEN_SEC : 1.0f;
    g_open = g_open < aim ? std::fmin(aim, g_open + step) : std::fmax(aim, g_open - step);
    if (s.tf != g_tf) { g_tf = s.tf; for (auto& j : g_joint) j = nullptr; }
}

void render_point() {
    for (auto& h : g_have) h = false;
    if (g_open <= 0.001f || g_tf == nullptr || g_poser) return;
    const float u = ease(g_open) * FINGER_OPEN_AMOUNT;
    for (int i = 0; i < N; ++i) {
        if (g_joint[i] == nullptr) g_joint[i] = joint_by_name(g_tf, LEFT_FINGERS[i]);
        MO* j = g_joint[i];
        Quat anim, rest;
        if (j == nullptr || !get_q(JOINT, j, "get_LocalRotation", anim) || !get_q(JOINT, j, "get_BaseLocalRotation", rest)) continue;
        g_target[i] = nlerp(qnorm(anim), qnorm(rest), u);
        g_have[i] = true;
        set_any(JOINT, j, "set_LocalRotation", &g_target[i]);
    }
}

void begin_render() {
    if (g_open <= 0.001f || g_poser) return;
    for (int i = 0; i < N; ++i)
        if (g_have[i] && g_joint[i] != nullptr) set_any(JOINT, g_joint[i], "set_LocalRotation", &g_target[i]);
}

} // namespace vn::fingers
