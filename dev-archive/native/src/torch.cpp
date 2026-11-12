// torch.cpp -- see torch.h. Visceral RE2's src/hands/flashlight.cpp is the model (the spot, the taps, the grip by the wrist);
// here the light itself is moved by Andyalpa's script (it can find the HandLight scene object; this plugin cannot), so this
// file only decides and tells it through the bridge.
#include "torch.h"
#include "bridge.h"
#include "reload.h"
#include "settings.h"

#include <cmath>

namespace vn::torch {

namespace S = vn::settings;

namespace {
bool g_hand = false;       // out of its spot
bool g_light = false;      // LT's switch
bool g_reverse = false;    // the overhand grip: the lens at the little-finger end
bool g_in_spot = false;    // the left hand is in the left shoulder spot
int g_logs = 0;

// the spot: the headset's position + the offset turned by its YAW only (Visceral RE2's holster spots, Tefa 2026-10-05:
// "no tilt please, just left and right turn"). Room space: +X right, +Y up, -Z forward.
Vec3 flat_forward() {
    Vec3 f = rotate(bridge::hmd_rot(), Vec3{0, 0, -1});
    f.y = 0;
    const float len = std::sqrt(f.x * f.x + f.z * f.z);
    return len < 1e-4f ? Vec3{0, 0, -1} : f * (1.0f / len);
}
Vec3 spot_pos() {
    const Vec3 f = flat_forward();
    const Vec3 right{-f.z, 0, f.x};
    return bridge::hmd_pos() + right * S::TORCH_SPOT_SIDE + Vec3{0, S::TORCH_SPOT_UP, 0} + f * S::TORCH_SPOT_FWD;
}

// the turn that makes local -Z (the way the IES light and the camera face) point along dir, world up kept up
Quat facing(Vec3 dir) {
    const float l = std::sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z);
    if (l < 1e-5f) return {0, 0, 0, 1};
    const Vec3 z = dir * (-1.0f / l);
    Vec3 up{0, 1, 0};
    if (std::fabs(z.y) > 0.98f) up = {0, 0, 1};
    auto cross = [](Vec3 a, Vec3 b) { return Vec3{a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; };
    Vec3 x = cross(up, z);
    x = x * (1.0f / std::sqrt(x.x * x.x + x.y * x.y + x.z * x.z));
    const Vec3 y = cross(z, x);
    const float tr = x.x + y.y + z.z;
    Quat q;
    if (tr > 0) { const float s = std::sqrt(tr + 1.0f) * 2; q = {(y.z - z.y) / s, (z.x - x.z) / s, (x.y - y.x) / s, 0.25f * s}; }
    else if (x.x > y.y && x.x > z.z) { const float s = std::sqrt(1.0f + x.x - y.y - z.z) * 2; q = {0.25f * s, (y.x + x.y) / s, (z.x + x.z) / s, (y.z - z.y) / s}; }
    else if (y.y > z.z) { const float s = std::sqrt(1.0f + y.y - x.x - z.z) * 2; q = {(y.x + x.y) / s, 0.25f * s, (z.y + y.z) / s, (z.x - x.z) / s}; }
    else { const float s = std::sqrt(1.0f + z.z - x.x - y.y) * 2; q = {(z.x + x.z) / s, (z.y + y.z) / s, 0.25f * s, (x.y - y.x) / s}; }
    return qnorm(q);
}

void publish(bool beam_ok, Vec3 pos, Quat rot) {
    bridge::put(bridge::S_TORCH, 4.0f + (g_hand ? 1.0f : 0.0f) + (g_light ? 2.0f : 0.0f) + (beam_ok ? 8.0f : 0.0f));
    bridge::put(bridge::S_TORCH_POS, pos.x); bridge::put((bridge::Slot)(bridge::S_TORCH_POS + 1), pos.y); bridge::put((bridge::Slot)(bridge::S_TORCH_POS + 2), pos.z);
    bridge::put(bridge::S_TORCH_ROT, rot.x); bridge::put((bridge::Slot)(bridge::S_TORCH_ROT + 1), rot.y);
    bridge::put((bridge::Slot)(bridge::S_TORCH_ROT + 2), rot.z); bridge::put((bridge::Slot)(bridge::S_TORCH_ROT + 3), rot.w);
}

// the beam out of the left fist: the lens at whichever end of the fist points forward (the controller's -Z = the thumb end)
bool beam(Vec3& pos, Quat& rot) {
    const Quat lq = bridge::view_quat(bridge::S_LROT);
    if (!bridge::has(lq.x)) return false;
    const Vec3 thumb_end = rotate(lq, Vec3{0, 0, -1});   // room space
    const Vec3 f = flat_forward();
    const float dot = thumb_end.x * f.x + thumb_end.y * f.y + thumb_end.z * f.z;
    const bool want = g_reverse ? !(dot > S::TORCH_FLIP_DOT) : dot < -S::TORCH_FLIP_DOT;
    if (want != g_reverse) {
        g_reverse = want;
        LOGI("%s torch: grip -> %s (thumb end . forward %.2f)", TAG, g_reverse ? "OVERHAND (lens at the little finger)" : "ORDINARY (lens at the thumb)", dot);
    }
    const Vec3 dir_room = g_reverse ? thumb_end * -1.0f : thumb_end;
    // the drawn hand sits praydog's offset ahead of the controller (re8vr.left_hand_position_offset, in the controller's
    // own axes, bridge S_LHAND_OFF): the fist is there, so the lens is measured from it
    Vec3 hand = bridge::hand_pos(bridge::LEFT);
    const float ox = bridge::view(bridge::S_LHAND_OFF);
    if (bridge::has(ox)) hand = hand + rotate(lq, Vec3{ox, bridge::view((bridge::Slot)(bridge::S_LHAND_OFF + 1)), bridge::view((bridge::Slot)(bridge::S_LHAND_OFF + 2))});
    const Vec3 lens_room = hand + dir_room * S::TORCH_LENS_M;
    Vec3 dir;
    if (!bridge::room_to_world(lens_room, pos) || !bridge::room_dir_to_world(dir_room, dir)) return false;
    rot = facing(dir);
    return true;
}
} // namespace

bool in_hand() { return g_hand; }

void frame() {
    if (!S::TORCH_ON || !bridge::live()) return;
    const bool was_in = g_in_spot;
    const float d = dist(bridge::hand_pos(bridge::LEFT), spot_pos());
    g_in_spot = was_in ? d < S::TORCH_SPOT_LEAVE_M : d < S::TORCH_SPOT_ENTER_M;
    if (g_in_spot && !was_in) bridge::rumble(bridge::LEFT, S::TORCH_BUZZ_ENTER_AMP, S::TORCH_BUZZ_ENTER_SEC, S::TORCH_BUZZ_HZ);

    // LG tapped in the spot: out / back (Tefa: "tap LG in the shoulder holster to bring it out, tap LG again to put it back")
    if (g_in_spot && bridge::pressed(bridge::S_LGRIP) && !bridge::lgrip_swallowed()) {
        g_hand = !g_hand;
        bridge::rumble(bridge::LEFT, S::TORCH_BUZZ_GRAB_AMP, S::TORCH_BUZZ_GRAB_SEC, S::TORCH_BUZZ_HZ);
        LOGI("%s torch: %s (light %s)", TAG, g_hand ? "TAKEN OUT into the left hand" : "PUT BACK in the left shoulder spot", g_light ? "on" : "off");
    }
    // LT: in the hand anywhere, or with the hand in the spot; never with LG held (LG + LT racks) or while a reload has the hand
    if (bridge::pressed(bridge::S_LTRIG) && !bridge::held(bridge::S_LGRIP) && (g_hand ? !reload::session_active() : g_in_spot)) {
        g_light = !g_light;
        bridge::rumble(bridge::LEFT, S::TORCH_BUZZ_GRAB_AMP, S::TORCH_BUZZ_GRAB_SEC, S::TORCH_BUZZ_HZ);
        LOGI("%s torch: light switched %s (torch %s)", TAG, g_light ? "ON" : "OFF", g_hand ? "in the hand" : "in its spot");
    }

    Vec3 pos{0, 0, 0};
    Quat rot{0, 0, 0, 1};
    const bool ok = g_hand && beam(pos, rot);
    if (g_hand && !ok && g_logs < 5) { ++g_logs; LOGW("%s torch: no beam place this frame (left controller or camera not read)", TAG); }
    publish(ok, pos, rot);
}

} // namespace vn::torch
