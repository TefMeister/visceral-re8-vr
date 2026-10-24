// smooth.cpp -- see smooth.h
#include "smooth.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "rack.h"
#include "reload.h"
#include "settings.h"

namespace vn::smooth {

using namespace joints;
using namespace vn::settings;

namespace {
enum Owner : int { CONTROLLER = 0, GRIP = 1, RACK = 2, MAG = 3 };
const char* owner_name(int o) {
    return o == GRIP ? "the two-handed grip" : o == RACK ? "the slide / pump / bolt" : o == MAG ? "the magazine going in" : "the controller";
}

bool g_have = false;
int g_owner = CONTROLLER;
float g_t0 = -10.0f;
Vec3 g_off_p{};                    // the gap at the change, in the gun hand's frame
Quat g_off_q{0, 0, 0, 1};
Vec3 g_final_p{};                  // what was last drawn, in the gun hand's frame
Quat g_final_q{0, 0, 0, 1};
float g_frame = -1.0f;             // the game solves the arm twice a frame: the second solve gets the same answer

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
    // 2026-10-24 first wear: "there is a frame right after i press LG that already shows the hand docked". The scope's grip
    // script docks the hand in a LATER solve of the same frame, after this had decided the frame, and that solve drew the
    // dock unsmoothed. So a later solve asking for a place within a dock's reach of the first answer draws the first answer.
    // (Build 2 instead eased any ask that moved between solves: the later solves also ask for places 0.4-0.7 m away every
    // frame, so the free hand was dragged with the gun and lagged -- Tefa: "super janky". Those far asks are left alone
    // again, as in build 1, where nothing looked wrong with them.)
    if (g_have && frame == g_frame) {
        if (now_s() - g_t0 < SMOOTH_DOCK_SEC || dist(rel, g_final_p) <= SMOOTH_LATE_DOCK_M)
            player::set_pose(target_of(ik), rp + rotate(rq, g_final_p), qnorm(qmul(rq, g_final_q)));
        return;
    }
    g_frame = frame;
    const int owner = rack::active() ? RACK : reload::hand_on_mag() ? MAG : bridge::flag(bridge::S_GRIPPING_WEAPON) ? GRIP : CONTROLLER;
    if (!g_have) {
        g_have = true;
        g_owner = owner;
        g_final_p = rel;
        g_final_q = qrel;
        return;
    }
    if (owner != g_owner) {
        g_off_p = g_final_p - rel;
        g_off_q = qnorm(qmul(g_final_q, qinv(qrel)));
        g_t0 = now_s();
        LOGI("%s smooth: left hand %s -> %s, eased over %.2f s (gap %.3f m)", TAG, owner_name(g_owner), owner_name(owner), SMOOTH_DOCK_SEC,
             dist(g_final_p, rel));
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
