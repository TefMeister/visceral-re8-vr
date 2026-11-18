// walls.cpp -- see walls.h
#include "walls.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "settings.h"

#include <cmath>

namespace vn::walls {

using namespace vn::settings;

namespace {
float g_log_t[2] = {-10.0f, -10.0f};
inline float dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }

bool fresh(bridge::Slot stamp_slot) {
    const float stamp = bridge::view(stamp_slot), frame = bridge::view(bridge::S_FRAME);
    // (not bridge::has(): it calls anything from 499 up "no value", and the frame count passes that a few seconds in;
    // the first simulator run, 2026-11-18, stood down every frame for it)
    return std::isfinite(stamp) && std::isfinite(frame) && stamp >= 0.5f && stamp >= frame + 1.0f - (float)WALLS_STALE_FRAMES;
}

// the hand's stop plane: the target moved onto the player's side of it (false = nothing to do)
bool plane_push(int side, Vec3& tp, float& pushed) {
    if (!fresh(side == 0 ? bridge::S_WALL_L_ON : bridge::S_WALL_R_ON)) return false;   // no wall lately
    const Vec3 p = bridge::view_vec3(side == 0 ? bridge::S_WALL_L_P : bridge::S_WALL_R_P);
    Vec3 n = bridge::view_vec3(side == 0 ? bridge::S_WALL_L_N : bridge::S_WALL_R_N);
    if (!std::isfinite(p.x) || !std::isfinite(p.y) || !std::isfinite(p.z) || !std::isfinite(n.x)) return false;   // world metres may pass 499 too
    const float nl = std::sqrt(dot(n, n));
    if (nl < 0.5f) return false;
    n = n * (1.0f / nl);
    const float d = dot(tp - p, n);   // < 0 = the hand is past the stop plane, into the wall
    if (d >= 0.0f || d < -WALLS_MAX_PUSH_M) return false;   // in front of it, or so far through that the plane is not this hand's wall
    tp = tp - n * d;
    pushed = -d;
    return true;
}

// the gun's turn at the wrist (right hand): put on once per placing of the target. The game can solve the arm more than
// once a frame with the same target, so a target that already carries the turn we wrote is left alone.
Quat g_written{0, 0, 0, 1};
bool g_written_ok = false;
bool tilt(Quat& tq) {
    if (!fresh(bridge::S_WALL_TILT_ON)) { g_written_ok = false; return false; }
    Quat dq{bridge::view(bridge::S_WALL_TILT_Q), bridge::view((bridge::Slot)(bridge::S_WALL_TILT_Q + 1)),
            bridge::view((bridge::Slot)(bridge::S_WALL_TILT_Q + 2)), bridge::view((bridge::Slot)(bridge::S_WALL_TILT_Q + 3))};
    if (!std::isfinite(dq.x) || !std::isfinite(dq.w) || std::fabs(dq.w) > 0.99999f) return false;   // none, or too small to see
    dq = qnorm(dq);
    if (g_written_ok && std::fabs(tq.x * g_written.x + tq.y * g_written.y + tq.z * g_written.z + tq.w * g_written.w) > 0.999999f) return false;
    tq = qnorm(qmul(dq, tq));
    g_written = tq;
    g_written_ok = true;
    return true;
}
} // namespace

void on_ik(MO* ik) {
    if (!WALLS_ON || !bridge::live()) return;
    const auto& s = player::now();
    const int side = ik == s.ik_left ? 0 : ik == s.ik_right ? 1 : -1;
    if (side < 0) return;
    MO* target = field_obj(ik, "Target");
    Vec3 tp;
    Quat tq;
    if (target == nullptr || !player::get_pose(target, tp, tq)) return;
    float pushed = 0.0f;
    const bool moved = plane_push(side, tp, pushed);
    const bool turned = side == 1 && tilt(tq);
    if (!moved && !turned) return;
    player::set_pose(target, tp, tq);
    const float t = joints::now_s();
    if (t - g_log_t[side] > 1.0f) {
        g_log_t[side] = t;
        if (moved) LOGI("%s walls: the %s hand stopped at a wall (it would have gone %.0f cm in)", TAG, side == 0 ? "left" : "right", pushed * 100.0f);
        if (turned) LOGI("%s walls: the gun turned at the wrist, away from a wall", TAG);
    }
}

} // namespace vn::walls
