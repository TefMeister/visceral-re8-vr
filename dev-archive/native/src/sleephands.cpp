// sleephands.cpp -- see sleephands.h
#include "sleephands.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "settings.h"

#include <cmath>

namespace vn::sleephands {

using namespace vn::settings;
using namespace vn::joints;

namespace {
struct Hand {
    const char* name;
    bridge::Slot pos, rot;
    float last[7] = {};
    bool have = false;
    int still = 0;          // frames in a row with not one number changed
    bool asleep = false;
    bool moved = false;     // it has moved since the launch: a live VR controller (flat play never moves one)
    float w = 0.0f;         // 0 = on the controller, 1 = at rest by the hip
};
Hand g_hands[2] = {{"left", bridge::S_LPOS, bridge::S_LROT}, {"right", bridge::S_RPOS, bridge::S_RROT}};
float g_last_t = -1.0f;

float ease(float t) { return t * t * (3.0f - 2.0f * t); }

void read(Hand& h) {
    float v[7];
    for (int i = 0; i < 3; ++i) v[i] = bridge::view((bridge::Slot)(h.pos + i));
    for (int i = 0; i < 4; ++i) v[3 + i] = bridge::view((bridge::Slot)(h.rot + i));
    for (float f : v) if (!bridge::has(f)) { h.have = false; h.still = 0; return; }
    bool same = h.have;
    for (int i = 0; i < 7 && same; ++i) same = v[i] == h.last[i];
    for (int i = 0; i < 7; ++i) h.last[i] = v[i];
    h.have = true;
    h.still = same ? h.still + 1 : 0;
    if (!same && h.have) h.moved = true;
}

// where the hand rests: in the room from the headset, then into the world
bool rest_world(int side, Vec3& out) {
    float p[3], q[4];
    for (int i = 0; i < 3; ++i) p[i] = bridge::view((bridge::Slot)(bridge::S_HMD_POS + i));
    for (int i = 0; i < 4; ++i) q[i] = bridge::view((bridge::Slot)(bridge::S_HMD_ROT + i));
    for (float f : p) if (!bridge::has(f)) return false;
    for (float f : q) if (!bridge::has(f)) return false;
    const Quat hq = qnorm(Quat{q[0], q[1], q[2], q[3]});
    Vec3 fwd = rotate(hq, Vec3{0, 0, -1});   // OpenXR room: -Z ahead, +Y up
    fwd.y = 0.0f;
    const float fl = std::sqrt(fwd.x * fwd.x + fwd.z * fwd.z);
    if (fl < 1e-4f) return false;
    fwd = fwd * (1.0f / fl);
    const Vec3 right{-fwd.z, 0.0f, fwd.x};   // ahead turned a quarter to the right about up
    const float s = side == 0 ? -1.0f : 1.0f;
    const Vec3 room = Vec3{p[0], p[1], p[2]} + Vec3{0, -SLEEP_DOWN_M, 0} + right * (s * SLEEP_SIDE_M) + fwd * SLEEP_FWD_M;
    return bridge::room_to_world(room, out);
}
} // namespace

void frame() {
    if (!SLEEP_HANDS_ON) return;
    const float t = now_s();
    const float dt = g_last_t < 0.0f ? 0.0f : std::fmin(0.1f, t - g_last_t);
    g_last_t = t;
    for (auto& h : g_hands) {
        read(h);
        const bool asleep = h.moved && h.have && h.still >= SLEEP_FRAMES;   // (not S_HMD: it may drop with the controllers)
        if (asleep != h.asleep) {
            h.asleep = asleep;
            LOGI("%s sleephands: the %s controller %s", TAG, h.name,
                 asleep ? "has gone to sleep (not one change for a while): its hand goes down to the side" : "woke up: its hand goes back to it");
        }
        const float step = dt / (asleep ? SLEEP_EASE_IN_S : SLEEP_EASE_OUT_S);
        h.w = asleep ? std::fmin(1.0f, h.w + step) : std::fmax(0.0f, h.w - step);
    }
}

void on_ik(MO* ik) {
    if (!SLEEP_HANDS_ON) return;
    const auto& s = player::now();
    const int side = ik == s.ik_left ? 0 : ik == s.ik_right ? 1 : -1;
    if (side < 0 || g_hands[side].w <= 0.0f) return;
    MO* target = field_obj(ik, "Target");
    Vec3 tp, rest;
    Quat tq;
    if (target == nullptr || !player::get_pose(target, tp, tq) || !rest_world(side, rest)) return;
    const float k = ease(g_hands[side].w);
    player::set_pose(target, tp + (rest - tp) * k, tq);
}

} // namespace vn::sleephands
