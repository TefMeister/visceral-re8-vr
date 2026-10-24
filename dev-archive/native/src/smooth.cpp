// smooth.cpp -- see smooth.h
#include "smooth.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "rack.h"
#include "settings.h"

namespace vn::smooth {

using namespace joints;
using namespace vn::settings;

namespace {
enum Owner : int { CONTROLLER = 0, GRIP = 1, RACK = 2 };
const char* owner_name(int o) { return o == GRIP ? "the two-handed grip" : o == RACK ? "the slide / pump / bolt" : "the controller"; }

bool g_have = false;
int g_owner = CONTROLLER;
float g_t0 = -10.0f;
Vec3 g_off_p{};                    // the gap at the change, in the gun hand's frame
Quat g_off_q{0, 0, 0, 1};
Vec3 g_final_p{};                  // what was last drawn, in the gun hand's frame
Quat g_final_q{0, 0, 0, 1};
float g_frame = -1.0f;             // the game solves the arm twice a frame: the second solve gets the same answer
Vec3 g_req_p{};                    // the last place asked for (in the gun hand's frame), to spot a jump
int g_jumps_logged = 0;

Quat slerp_from_identity(Quat q, float k) {   // identity -> q by k (0..1), the short way
    if (q.w < 0.0f) q = Quat{-q.x, -q.y, -q.z, -q.w};
    const float w = std::fmin(1.0f, q.w);
    const float a = std::acos(w);
    const float s = std::sin(a);
    if (s < 1e-5f) return Quat{0, 0, 0, 1};
    const float f = std::sin(k * a) / s;
    return qnorm(Quat{q.x * f, q.y * f, q.z * f, std::cos(k * a)});
}
MO* target_of(MO* ik) { return field_obj(ik, "Target"); }
} // namespace

void on_ik(MO* ik) {
    const auto& s = player::now();
    if (ik != s.ik_left) return;
    if (bridge::experiment(bridge::EX_NO_SMOOTH) || !bridge::live()) { g_have = false; return; }
    Vec3 rp, lp;
    Quat rq, lq;
    if (!player::get_pose(target_of(s.ik_right), rp, rq) || !player::get_pose(target_of(ik), lp, lq)) return;
    const Quat inv = qinv(qnorm(rq));
    const Vec3 rel = rotate(inv, lp - rp);
    const Quat qrel = qnorm(qmul(inv, qnorm(lq)));
    const float frame = bridge::view(bridge::S_FRAME);
    // 2026-10-24 first wear: "there is a frame right after i press LG that already shows the hand docked and then the smooth
    // animation continues". The scope's grip script docks the hand in a LATER solve of the same frame (it calls the solve
    // itself), after this had already decided the frame, so that solve drew the dock unsmoothed. So a later solve that asks
    // for a different place is a new ask, and any ask that jumps (whoever made it, owner flag or not) is eased.
    bool jump = false;
    const bool mid = g_have && frame == g_frame;
    if (mid) {   // a later solve in the same frame: the same ask, or our own eased place written by the first solve
        if (dist(rel, g_req_p) <= SMOOTH_SAME_M || dist(rel, g_final_p) <= SMOOTH_SAME_M) {
            if (now_s() - g_t0 < SMOOTH_DOCK_SEC) player::set_pose(target_of(ik), rp + rotate(rq, g_final_p), qnorm(qmul(rq, g_final_q)));
            return;
        }
        jump = true;   // someone moved the hand between this frame's solves
    } else if (g_have) {
        jump = dist(rel, g_req_p) > SMOOTH_JUMP_M;
    }
    g_frame = frame;
    const int owner = rack::active() ? RACK : bridge::flag(bridge::S_GRIPPING_WEAPON) ? GRIP : CONTROLLER;
    if (!g_have) {
        g_have = true;
        g_owner = owner;
        g_req_p = g_final_p = rel;
        g_final_q = qrel;
        return;
    }
    const float jump_m = dist(rel, g_req_p);
    g_req_p = rel;
    if (owner != g_owner || jump) {
        g_off_p = g_final_p - rel;
        g_off_q = qnorm(qmul(g_final_q, qinv(qrel)));
        g_t0 = now_s();
        if (owner != g_owner)
            LOGI("%s smooth: left hand %s -> %s, eased over %.2f s (gap %.3f m)", TAG, owner_name(g_owner), owner_name(owner), SMOOTH_DOCK_SEC,
                 dist(g_final_p, rel));
        else if (g_jumps_logged < 40) {
            ++g_jumps_logged;
            LOGI("%s smooth: the left hand was asked to jump %.3f m (%s) under %s, eased over %.2f s (gap %.3f m)", TAG, jump_m,
                 mid ? "between two solves of one frame" : "in one frame", owner_name(owner), SMOOTH_DOCK_SEC, dist(g_final_p, rel));
        }
        g_owner = owner;
    }
    const float k = 1.0f - ease((now_s() - g_t0) / SMOOTH_DOCK_SEC);
    if (k <= 0.0f) {
        g_final_p = rel;
        g_final_q = qrel;
        return;
    }
    g_final_p = rel + g_off_p * k;
    g_final_q = qnorm(qmul(slerp_from_identity(g_off_q, k), qrel));
    player::set_pose(target_of(ik), rp + rotate(rq, g_final_p), qnorm(qmul(rq, g_final_q)));
}

} // namespace vn::smooth
