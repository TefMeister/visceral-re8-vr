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
}

void on_ik(MO* ik) {
    if (!WALLS_ON || !bridge::live()) return;
    const auto& s = player::now();
    const int side = ik == s.ik_left ? 0 : ik == s.ik_right ? 1 : -1;
    if (side < 0) return;
    const bridge::Slot on = side == 0 ? bridge::S_WALL_L_ON : bridge::S_WALL_R_ON;
    const float stamp = bridge::view(on), frame = bridge::view(bridge::S_FRAME);
    if (!bridge::has(stamp) || !bridge::has(frame) || stamp < frame + 1.0f - (float)WALLS_STALE_FRAMES) return;   // no wall lately
    const Vec3 p = bridge::view_vec3(side == 0 ? bridge::S_WALL_L_P : bridge::S_WALL_R_P);
    Vec3 n = bridge::view_vec3(side == 0 ? bridge::S_WALL_L_N : bridge::S_WALL_R_N);
    if (!bridge::has(p.x) || !bridge::has(n.x)) return;
    const float nl = std::sqrt(dot(n, n));
    if (nl < 0.5f) return;
    n = n * (1.0f / nl);
    MO* target = field_obj(ik, "Target");
    Vec3 tp;
    Quat tq;
    if (target == nullptr || !player::get_pose(target, tp, tq)) return;
    const float d = dot(tp - p, n);   // < 0 = the hand is past the stop plane, into the wall
    if (d >= 0.0f || d < -WALLS_MAX_PUSH_M) return;   // in front of it, or so far through that the plane is not this hand's wall
    player::set_pose(target, tp - n * d, tq);
    const float t = joints::now_s();
    if (t - g_log_t[side] > 1.0f) {
        g_log_t[side] = t;
        LOGI("%s walls: the %s hand stopped at a wall (it would have gone %.0f cm in)", TAG, side == 0 ? "left" : "right", -d * 100.0f);
    }
}

} // namespace vn::walls
