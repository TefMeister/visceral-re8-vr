// righthand.cpp -- see righthand.h
#include "righthand.h"
#include "bridge.h"
#include "fingers.h"
#include "gate.h"
#include "joints.h"
#include "player.h"
#include "rack.h"
#include "reload.h"
#include "settings.h"

#include <cmath>

namespace vn::righthand {

using namespace joints;
using namespace vn::settings;

namespace {
constexpr int N = 15;
const wchar_t* const RIGHT[N] = {
    L"R_IndexF1", L"R_IndexF2", L"R_IndexF3", L"R_MiddleF1", L"R_MiddleF2", L"R_MiddleF3",
    L"R_RingF1", L"R_RingF2", L"R_RingF3", L"R_PinkyF1", L"R_PinkyF2", L"R_PinkyF3",
    L"R_Thumb1", L"R_Thumb2", L"R_Thumb3",
};
const wchar_t* const LEFT[N] = {
    L"L_IndexF1", L"L_IndexF2", L"L_IndexF3", L"L_MiddleF1", L"L_MiddleF2", L"L_MiddleF3",
    L"L_RingF1", L"L_RingF2", L"L_RingF3", L"L_PinkyF1", L"L_PinkyF2", L"L_PinkyF3",
    L"L_Thumb1", L"L_Thumb2", L"L_Thumb3",
};

Quat nlerp(Quat a, Quat b, float u) {
    if (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w < 0.0f) b = {-b.x, -b.y, -b.z, -b.w};
    return qnorm({a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, a.z + (b.z - a.z) * u, a.w + (b.w - a.w) * u});
}

// one hand's fingers eased to the skeleton's rest turn (Village's relaxed curl) and written after the animation
struct Still {
    const wchar_t* const* names;
    const char* side;
    MO* tf = nullptr;
    MO* joint[N] = {};
    Quat rest[N] = {};
    bool rest_ok[N] = {};
    Quat target[N] = {};
    bool have[N] = {};
    float k = 0.0f, last_t = -1.0f;
    bool was = false;
    bool pending = false;    // 2026-11-02: a change of want must last STILL_DEBOUNCE_S before it counts (the twitch)
    float since = 0.0f;
    float phase = 0.0f;      // the sway's offset for this hand, so the two hands never move together

    void render(MO* skel, bool want, const char* why) {
        for (auto& h : have) h = false;
        if (skel != tf) { tf = skel; for (int i = 0; i < N; ++i) { joint[i] = nullptr; rest_ok[i] = false; } }
        const float t = now_s(), dt = last_t < 0.0f ? 0.0f : std::fmin(0.1f, t - last_t);
        last_t = t;
        want = want && tf != nullptr;
        // 2026-11-02 (Tefa: "left hand is twitching when walking, not animating anymore but jittery"): the free left hand's
        // want flipped many times a second (the game docking it while LG is up, put back by smooth.cpp), each flip easing
        // the fingers between still and animated. A flip now counts only once it has lasted STILL_DEBOUNCE_S
        if (want != pending) { pending = want; since = t; }
        if (pending != was && t - since >= STILL_DEBOUNCE_S) { was = pending; LOGI("%s righthand: %s fingers %s", TAG, side, was ? why : "back to the game's"); }
        const float step = RIGHT_STILL_SEC > 0.0f ? dt / RIGHT_STILL_SEC : 1.0f;
        k = was ? std::fmin(1.0f, k + step) : std::fmax(0.0f, k - step);
        if (k <= 0.0f || tf == nullptr) return;
        const float u = ease(k);
        for (int i = 0; i < N; ++i) {
            if (joint[i] == nullptr) joint[i] = joint_by_name(tf, names[i]);
            MO* j = joint[i];
            if (j == nullptr) continue;
            if (!rest_ok[i]) { Quat r; if (!get_q(JOINT, j, "get_BaseLocalRotation", r)) continue; rest[i] = qnorm(r); rest_ok[i] = true; }
            Quat cur;
            if (!get_q(JOINT, j, "get_LocalRotation", cur)) continue;
            // 2026-11-02 (Tefa: "both need a subtle finger sway that is not tied to movement just natural subtle hand
            // movement"): a slow drift of each finger's curl about the rest pose, two slow waves per finger, phased apart
            const int f = i / 3;
            const float w = (i % 3 == 0) ? 0.6f : (i % 3 == 1) ? 1.0f : 0.8f;   // base, middle, tip
            const float a = FINGER_SWAY_DEG * w * (0.6f * std::sin(t * FINGER_SWAY_W1 + f * 1.3f + phase) + 0.4f * std::sin(t * FINGER_SWAY_W2 + f * 2.1f + phase * 0.7f));
            const float h = a * 3.14159265f / 360.0f;
            const Quat sway = qnorm(qmul(rest[i], Quat{0, 0, std::sin(h), std::cos(h)}));
            target[i] = nlerp(qnorm(cur), sway, u);
            have[i] = true;
            set_any(JOINT, j, "set_LocalRotation", &target[i]);
        }
    }
    void again() const {
        for (int i = 0; i < N; ++i)
            if (have[i] && joint[i] != nullptr) set_any(JOINT, joint[i], "set_LocalRotation", &target[i]);
    }
};
Still g_right{RIGHT, "right"};
Still g_left{LEFT, "left"};
struct PhaseInit { PhaseInit() { g_left.phase = 2.4f; } } g_phase_init;
} // namespace

void render_point() {
    const auto& s = player::now();
    const bool play = bridge::live() && bridge::flag(bridge::S_CAN_USE_HANDS) && !bridge::flag(bridge::S_CUTSCENE);
    g_right.render(s.tf, RIGHT_STILL_ON && play && s.weapon == nullptr, "held still: no weapon out (the relaxed rest pose)");
    // 2026-11-01 23:3x (Tefa: "left hand is still animating while walking"): the left fingers the same, whenever the left hand
    // is free: not gripping or holding anything, no Hand Poser on it, and not opening toward a part (fingers.cpp)
    // (2026-11-02: the game's own "gripping" flag left out: it flickers while LG is up, the game docking the free hand)
    const bool left_free = !bridge::held(bridge::S_LGRIP) && !rack::active() &&
                           !reload::mag_in_hand() && !reload::round_in_hand() && !gate::owns_left() &&
                           bridge::view(bridge::S_POSER_HELD) <= 0.5f && !fingers::busy();
    g_left.render(s.tf, LEFT_STILL_ON && play && left_free, "held still: the left hand is free (the relaxed rest pose)");
}

void begin_render() { g_right.again(); g_left.again(); }

} // namespace vn::righthand
