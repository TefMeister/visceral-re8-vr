// righthand.cpp -- see righthand.h
#include "righthand.h"
#include "bridge.h"
#include "breech.h"
#include "fingers.h"
#include "gate.h"
#include "joints.h"
#include "player.h"
#include "rack.h"
#include "rack_right.h"
#include "recoil.h"
#include "reload.h"
#include "settings.h"
#include "shellclip.h"

#include <cmath>
#include <array>
#include <map>
#include <string>

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

    void render(MO* skel, bool want, const char* why, bool sway_on = true) {
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
            // 2026-11-09 (Tefa: "while a gun is in hand and no button is pressed, hand must still not move slightly and subtly, that is
            // only when there is nothing in hand at all"): the sway only with nothing in hand; with a gun out the free hand is still
            const float a = !sway_on ? 0.0f : FINGER_SWAY_DEG * w * (0.6f * std::sin(t * FINGER_SWAY_W1 + f * 1.3f + phase) + 0.4f * std::sin(t * FINGER_SWAY_W2 + f * 2.1f + phase * 0.7f));
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
// 2026-11-09 (Tefa: "hand pose on the gun must always be the pose it has when a shot has just been fired, firmly on the grip, right
// now after a shot is fired, about 3-5 seconds later the hand loosens and starts the subtle movement animation"): the right fingers
// are read FIRM_CAPTURE_S after a live shot, kept per gun (until the game closes), and held from then on whenever that gun is in hand
// and the right hand has no other job (the bolt, the Wolfsbane's cover, a finger clip, a reload, a cutscene). Hand Poser, which
// writes after this, still wins on any joint it holds. Before the gun's first shot of a session its hand is the game's.
struct Firm {
    MO* tf = nullptr;
    MO* joint[N] = {};
    std::map<std::string, std::array<Quat, N>> kept;
    std::string gun;
    float caught_for = -1.0f;   // the shot already read
    float rt_t = -1.0f;         // when RT was last down
    float k = 0.0f, last_t = -1.0f;
    Quat target[N] = {};
    bool have[N] = {};

    bool find(MO* skel) {
        if (skel != tf) { tf = skel; for (auto& j : joint) j = nullptr; }
        if (tf == nullptr) return false;
        for (int i = 0; i < N; ++i) if (joint[i] == nullptr) joint[i] = joint_by_name(tf, RIGHT[i]);
        return true;
    }
    void render(MO* skel, const std::string& id, bool free_for_it) {
        for (auto& h : have) h = false;
        const float t = now_s(), dt = last_t < 0.0f ? 0.0f : std::fmin(0.1f, t - last_t);
        last_t = t;
        if (!FIRM_GRIP_ON || id.empty() || !find(skel)) { k = 0.0f; return; }
        // 2026-11-23 (b152; Tefa: "index finger moving with RT press on the trigger"): the firm grip held the index finger too, after
        // Hand Poser had bent it for the pull, so the trigger finger never moved once a gun had fired. While RT is down, and
        // FIRM_TRIGGER_FREE_S after, the three index joints (the first three of RIGHT) are not held and not read into the kept grip
        if (bridge::held(bridge::S_RTRIG)) rt_t = t;
        const bool trigger_free = rt_t >= 0.0f && t - rt_t < FIRM_TRIGGER_FREE_S;
        const float shot = recoil::last_shot_s();
        if (shot > 0.0f && shot != caught_for && t - shot >= FIRM_CAPTURE_S && t - shot < FIRM_CAPTURE_S + 0.5f) {
            caught_for = shot;
            std::array<Quat, N> q{};
            bool ok = true;
            for (int i = 0; i < N && ok; ++i) ok = joint[i] != nullptr && get_q(JOINT, joint[i], "get_LocalRotation", q[i]);
            if (ok && trigger_free) {   // the index finger is mid-pull: keep the one read before, or wait for a shot with RT let go
                auto old = kept.find(id);
                if (old == kept.end()) ok = false;
                else for (int i = 0; i < 3; ++i) q[i] = old->second[i];
            }
            if (ok) {
                const bool first = kept.find(id) == kept.end();
                kept[id] = q;
                if (first) LOGI("%s righthand: %s: the right hand's firm grip read from a shot; held from now on", TAG, id.c_str());
            }
        }
        auto it = kept.find(id);
        const bool want = free_for_it && it != kept.end();
        const float step = dt / FIRM_EASE_S;
        k = want ? std::fmin(1.0f, k + step) : std::fmax(0.0f, k - step);
        if (k <= 0.0f || it == kept.end()) return;
        const float u = ease(k);
        for (int i = 0; i < N; ++i) {
            Quat cur;
            if (trigger_free && i < 3) continue;   // the trigger finger is Hand Poser's during a pull
            if (joint[i] == nullptr || !get_q(JOINT, joint[i], "get_LocalRotation", cur)) continue;
            target[i] = nlerp(qnorm(cur), qnorm(it->second[i]), u);
            have[i] = true;
            set_any(JOINT, joint[i], "set_LocalRotation", &target[i]);
        }
    }
    void again() const {
        for (int i = 0; i < N; ++i)
            if (have[i] && joint[i] != nullptr) set_any(JOINT, joint[i], "set_LocalRotation", &target[i]);
    }
};
Firm g_firm;

Still g_right{RIGHT, "right"};
Still g_left{LEFT, "left"};
struct PhaseInit { PhaseInit() { g_left.phase = 2.4f; } } g_phase_init;
} // namespace

void render_point() {
    const auto& s = player::now();
    const bool play = bridge::live() && bridge::flag(bridge::S_CAN_USE_HANDS) && !bridge::flag(bridge::S_CUTSCENE);
    g_right.render(s.tf, RIGHT_STILL_ON && play && s.weapon == nullptr, "held still: no weapon out (the relaxed rest pose)");
    const bool right_free = play && s.gun != nullptr && !rack_right::active() && !gate::right_at_cover() && !gate::right_lifted() &&
                            !shellclip::playing_right() && !bridge::flag(bridge::S_IS_RELOADING);
    g_firm.render(s.tf, s.gun != nullptr ? s.weapon_id : std::string(), right_free && breech::latch_right_spot() == 0);   // b152: nor while the thumb is on / has flicked the GM 79's latch (Hand Poser's two latch poses)
    // 2026-11-01 23:3x (Tefa: "left hand is still animating while walking"): the left fingers the same, whenever the left hand
    // is free: not gripping or holding anything, no Hand Poser on it, and not opening toward a part (fingers.cpp)
    // (2026-11-02: the game's own "gripping" flag left out: it flickers while LG is up, the game docking the free hand)
    const bool left_free = !bridge::held(bridge::S_LGRIP) && !rack::active() && !shellclip::playing_left() &&
                           !reload::mag_in_hand() && !reload::round_in_hand() && !gate::owns_left() &&
                           bridge::view(bridge::S_POSER_HELD) <= 0.5f;   // (2026-11-02: no longer stands aside for fingers.cpp: that
                           // opening is written AFTER this now, on top of the still pose, so the two no longer take turns: the twitch)
    g_left.render(s.tf, LEFT_STILL_ON && play && left_free, "held still: the left hand is free (the relaxed rest pose)", s.weapon == nullptr);
}

// 2026-11-23 (b152; Tefa: "right hand index finger on the trigger ... index finger moving with RT press on the trigger"): the trigger
// finger's pull is made HERE, the last write of the frame, on every gun: while RT is down the three index joints are bent a little
// further (TRIGGER_PULL_DEG, about each joint's own z: Village's right-hand bend) on top of whatever pose stands, eased over
// TRIGGER_PULL_S. (Hand Poser's own "trigger pulled" pose never showed in Village: its write was not the last one. The loader gives
// no trigger travel, pressed or not only, so the finger goes by time, not by the squeeze.)
void trigger_pull() {
    static float k = 0.0f, last = -1.0f;
    static MO* tf = nullptr;
    static MO* jt[3] = {};
    static Quat base[3] = {};          // the finger as it stood at this frame's first call: BeginRendering comes twice a frame on
    static float base_frame = -1.0f;   // Two Frame Sequential, and bending what was already bent doubled the pull (measured)
    const auto& s = player::now();
    const float t = now_s(), dt = last < 0.0f ? 0.0f : std::fmin(0.1f, t - last);
    last = t;
    const bool play = bridge::live() && bridge::flag(bridge::S_CAN_USE_HANDS) && !bridge::flag(bridge::S_CUTSCENE);
    const bool want = TRIGGER_PULL_ON && play && s.gun != nullptr && bridge::held(bridge::S_RTRIG) && !rack_right::active() && !gate::right_at_cover();
    const float step = TRIGGER_PULL_S > 0.0f ? dt / TRIGGER_PULL_S : 1.0f;
    k = want ? std::fmin(1.0f, k + step) : std::fmax(0.0f, k - step);
    if (k <= 0.0f || s.tf == nullptr) return;
    if (s.tf != tf) { tf = s.tf; for (auto& j : jt) j = nullptr; }
    const float u = ease(k);
    const float frame = bridge::view(bridge::S_FRAME);
    const bool fresh = frame != base_frame;
    base_frame = frame;
    for (int i = 0; i < 3; ++i) {
        if (jt[i] == nullptr) jt[i] = joint_by_name(tf, RIGHT[i]);
        Quat cur;
        if (jt[i] == nullptr || !get_q(JOINT, jt[i], "get_LocalRotation", cur)) continue;
        if (fresh) base[i] = qnorm(cur);
        const float h = TRIGGER_PULL_DEG[i] * u * 3.14159265f / 360.0f;
        Quat q = qnorm(qmul(base[i], Quat{0, 0, std::sin(h), std::cos(h)}));
        set_any(JOINT, jt[i], "set_LocalRotation", &q);
    }
}

void begin_render() { g_right.again(); g_left.again(); g_firm.again(); trigger_pull(); }

} // namespace vn::righthand
