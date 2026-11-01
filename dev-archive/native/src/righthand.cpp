// righthand.cpp -- see righthand.h
#include "righthand.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "settings.h"

#include <cmath>

namespace vn::righthand {

using namespace joints;
using namespace vn::settings;

namespace {
const wchar_t* const FINGERS[] = {
    L"R_IndexF1", L"R_IndexF2", L"R_IndexF3", L"R_MiddleF1", L"R_MiddleF2", L"R_MiddleF3",
    L"R_RingF1", L"R_RingF2", L"R_RingF3", L"R_PinkyF1", L"R_PinkyF2", L"R_PinkyF3",
    L"R_Thumb1", L"R_Thumb2", L"R_Thumb3",
};
constexpr int N = sizeof(FINGERS) / sizeof(FINGERS[0]);
MO* g_tf = nullptr;
MO* g_joint[N] = {};
Quat g_rest[N] = {};
bool g_rest_ok[N] = {};
Quat g_target[N] = {};
bool g_have[N] = {};
float g_k = 0.0f, g_last_t = -1.0f;
bool g_was = false;

Quat nlerp(Quat a, Quat b, float u) {
    if (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w < 0.0f) b = {-b.x, -b.y, -b.z, -b.w};
    return qnorm({a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, a.z + (b.z - a.z) * u, a.w + (b.w - a.w) * u});
}
float ease(float x) { x = std::fmax(0.0f, std::fmin(1.0f, x)); return x * x * (3.0f - 2.0f * x); }
} // namespace

void render_point() {
    for (auto& h : g_have) h = false;
    if (!RIGHT_STILL_ON) return;
    const auto& s = player::now();
    if (s.tf != g_tf) { g_tf = s.tf; for (int i = 0; i < N; ++i) { g_joint[i] = nullptr; g_rest_ok[i] = false; } }
    const float t = now_s();
    const float dt = g_last_t < 0.0f ? 0.0f : std::fmin(0.1f, t - g_last_t);
    g_last_t = t;
    const bool play = bridge::live() && bridge::flag(bridge::S_CAN_USE_HANDS) && !bridge::flag(bridge::S_CUTSCENE);
    const bool want = play && g_tf != nullptr && s.weapon == nullptr;
    if (want != g_was) { g_was = want; LOGI("%s righthand: %s", TAG, want ? "no weapon out: the right fingers held still (the relaxed rest pose)" : "back to the game's"); }
    const float step = RIGHT_STILL_SEC > 0.0f ? dt / RIGHT_STILL_SEC : 1.0f;
    g_k = want ? std::fmin(1.0f, g_k + step) : std::fmax(0.0f, g_k - step);
    if (g_k <= 0.0f || g_tf == nullptr) return;
    const float u = ease(g_k);
    for (int i = 0; i < N; ++i) {
        if (g_joint[i] == nullptr) g_joint[i] = joint_by_name(g_tf, FINGERS[i]);
        MO* j = g_joint[i];
        if (j == nullptr) continue;
        if (!g_rest_ok[i]) { Quat r; if (!get_q(JOINT, j, "get_BaseLocalRotation", r)) continue; g_rest[i] = qnorm(r); g_rest_ok[i] = true; }
        Quat cur;
        if (!get_q(JOINT, j, "get_LocalRotation", cur)) continue;
        g_target[i] = nlerp(qnorm(cur), g_rest[i], u);
        g_have[i] = true;
        set_any(JOINT, j, "set_LocalRotation", &g_target[i]);
    }
}

void begin_render() {
    for (int i = 0; i < N; ++i)
        if (g_have[i] && g_joint[i] != nullptr) set_any(JOINT, g_joint[i], "set_LocalRotation", &g_target[i]);
}

} // namespace vn::righthand
