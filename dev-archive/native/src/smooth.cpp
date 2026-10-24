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
// 2026-10-24 (worn 15:39, Tefa: with the hand on the grip "hand jitters with handgun too while i walk, rifle does too"): the
// grip's place comes from the animation's socket, which the walk keeps moving. Once the hand has eased onto the grip, its place
// on the gun is frozen (in the gun hand's frame) until it lets go, so the walk cannot shake it
bool g_grip_frozen = false;
Vec3 g_grip_p{};
Quat g_grip_q{0, 0, 0, 1};

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
    // Build 5 (worn 13:49): that also held back the grip script's UNDO of the game's 10 cm dock (made without LG), so the
    // unwanted dock stayed on screen. A late ask that comes back toward the left controller is an undo: drawn as asked.
    if (g_have && frame == g_frame) {
        const bool easing = now_s() - g_t0 < SMOOTH_DOCK_SEC;
        Vec3 cp;
        const Vec3 first = rp + rotate(rq, g_final_p);
        // 2026-10-24 (Tefa: "when inserting the mag, left hand keeps rapidly going in the direction of the insertion and then
        // teleports back onto the mag"): while the hand is ours (slide / pump / bolt / magazine) the grip script's undo moved
        // it toward the controller in a later solve and that was drawn. Ours: the first answer always wins
        const bool ours = rack::active() || reload::hand_on_mag() || g_grip_frozen;
        // (worn 15:27, Tefa: gripping the handgun "hand jumps around a bit like fighting something", and walking with the rifle
        // gripped "the hand jitters a lot around the gripping area"): with LG held the grip is wanted, and the later solves'
        // pulls toward the controller were drawn every frame. An undo is only an undo with LG let go
        const bool lg = bridge::held(bridge::S_LGRIP);
        if (!ours && !lg && !easing && bridge::room_to_world(bridge::hand_pos(bridge::LEFT), cp) && dist(lp, cp) + SMOOTH_TOWARD_M < dist(first, cp)) {
            g_final_p = rel;
            g_final_q = qrel;
            return;
        }
        if (ours || easing || dist(rel, g_final_p) <= SMOOTH_LATE_DOCK_M) player::set_pose(target_of(ik), first, qnorm(qmul(rq, g_final_q)));
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
    if (owner != GRIP) g_grip_frozen = false;
    if (owner != g_owner) {
        g_off_p = g_final_p - rel;
        g_off_q = qnorm(qmul(g_final_q, qinv(qrel)));
        g_t0 = now_s();
        LOGI("%s smooth: left hand %s -> %s, eased over %.2f s (gap %.3f m)", TAG, owner_name(g_owner), owner_name(owner), SMOOTH_DOCK_SEC,
             dist(g_final_p, rel));
        g_owner = owner;
    }
    const float k = 1.0f - ease((now_s() - g_t0) / SMOOTH_DOCK_SEC);
    if (owner == GRIP && k <= 0.0f) {
        if (!g_grip_frozen) {
            g_grip_frozen = true;
            g_grip_p = rel;
            g_grip_q = qrel;
            LOGI("%s smooth: the left hand's place on the grip frozen (%.3f %.3f %.3f in the gun hand's frame)", TAG, rel.x, rel.y, rel.z);
        }
        g_final_p = g_grip_p;
        g_final_q = g_grip_q;
        player::set_pose(target_of(ik), rp + rotate(rq, g_final_p), qnorm(qmul(rq, g_final_q)));
        return;
    }
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
