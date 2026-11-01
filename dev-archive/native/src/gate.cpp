// gate.cpp -- see gate.h. Built on rack_right.cpp's way of holding a gun in the left hand (proven on the F2's bolt).
#include "gate.h"
#include "breech.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "reload.h"
#include "settings.h"
#include "weapons.h"

#include <algorithm>
#include <cmath>
#include <string>

namespace vn::gate {

using namespace joints;
using namespace vn::settings;

namespace {
struct Pose { Vec3 p; Quat q; };
Pose mul(const Pose& a, const Pose& b) { return {a.p + rotate(a.q, b.p), qnorm(qmul(a.q, b.q))}; }
Pose inverse(const Pose& a) { const Quat iq = qinv(qnorm(a.q)); return {rotate(iq, Vec3{-a.p.x, -a.p.y, -a.p.z}), iq}; }
Quat nlerp(Quat a, Quat b, float u) {
    if (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w < 0.0f) b = {-b.x, -b.y, -b.z, -b.w};
    return qnorm({a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, a.z + (b.z - a.z) * u, a.w + (b.w - a.w) * u});
}
Pose blend(const Pose& a, const Pose& b, float u) { return {lerp(a.p, b.p, u), nlerp(a.q, b.q, u)}; }
MO* target_of(MO* ik) { return field_obj(ik, "Target"); }
bool tf_pose(MO* tf, Pose& out) { return tf != nullptr && player::get_pose(tf, out.p, out.q); }
bool left_controller(Pose& out) {
    return bridge::room_to_world(bridge::hand_pos(bridge::LEFT), out.p) && bridge::room_rot_to_world(bridge::view_quat(bridge::S_LROT), out.q);
}
Quat axis_turn(const Vec3& ax, float deg) { const float h = deg * 3.14159265f / 360.0f, s = std::sin(h); return qnorm({ax.x * s, ax.y * s, ax.z * s, std::cos(h)}); }

enum class Phase { OFF, HELD, RETURN, HANDOVER, STAY };
const char* phase_name(Phase p) {
    return p == Phase::HELD ? "held by the left hand" : p == Phase::RETURN ? "right hand back to the grip" : p == Phase::HANDOVER ? "handed back" : p == Phase::STAY ? "left hand stays on the drum" : "off";
}
Phase g_phase = Phase::OFF;
std::string g_id;
MO* g_weapon_tf = nullptr;
bool g_was_open = false;

Pose g_gun_k{}, g_gun_s{}, g_gun_now{}, g_gun_in_right{};
float g_smooth_t = -1.0f;
bool g_now_ok = false;
Pose g_right_in_gun{}, g_left_in_gun{}, g_right_dock_in_gun{};
Pose g_left_from{};
float g_left_t0 = 0.0f;
Quat g_grip_left_turn{0, 0, 0, 1};   // the left hand's turn on the gun while the game's grip held it last
bool g_have_left_turn = false;
bool g_parented = false;
Vec3 g_local_p{};
Quat g_local_q{0, 0, 0, 1};

int g_rounds = 0;          // rounds in the right hand
bool g_rdock = false;      // the right hand at the cover
float g_ru = 0.0f, g_ru0 = 0.0f, g_rt0 = 0.0f;
bool g_need_turn = false;  // a round went in: LT must turn the drum before the next
int g_turns = 0;
float g_cyl_draw = 0.0f, g_cyl_t = -1.0f;
MO* g_cyl = nullptr;
Quat g_cyl_rest{0, 0, 0, 1};
bool g_cyl_ok = false;

float g_t0 = 0.0f, g_ho_sec = 0.3f;
Pose g_ret_from{}, g_ho_right{}, g_ho_gun{}, g_last_right{}, g_praydog{};
bool g_ho_left = false;
float g_praydog_frame = -1.0f;

Vec3 g_left_off = GATE_LEFT_OFF, g_right_off = GATE_RIGHT_OFF, g_cyl_axis = GATE_CYL_AXIS;

void put_local_back(const char* why) {
    if (g_weapon_tf != nullptr && g_parented) {
        set_any(XFORM, g_weapon_tf, "set_LocalPosition", &g_local_p);
        set_any(XFORM, g_weapon_tf, "set_LocalRotation", &g_local_q);
    }
    LOGI("%s gate: the gun back on the right hand (%s)", TAG, why);
}

bool take() {
    const auto& s = player::now();
    Pose lc{}, g0{}, rt0{}, lt0{};
    if (!left_controller(lc) || !tf_pose(s.weapon_tf, g0) || s.ik_right == nullptr || s.ik_left == nullptr ||
        !tf_pose(target_of(s.ik_right), rt0) || !tf_pose(target_of(s.ik_left), lt0)) {
        LOGW("%s gate: LG with the cover open, but the left controller / gun / hand targets could not be read: not taken", TAG);
        return false;
    }
    const Pose ig = inverse(g0);
    g_gun_k = mul(inverse(lc), g0);
    g_gun_in_right = mul(inverse(rt0), g0);
    g_right_in_gun = mul(ig, rt0);
    Vec3 cyl_in_gun{0.0f, 0.03f, 0.06f}, lid_in_gun{0.02f, 0.03f, 0.02f}, p{};
    MO* cyl = joint_by_name(s.weapon_tf, L"Cylinder");
    MO* lid = joint_by_name(s.weapon_tf, L"Lid");
    if (cyl != nullptr && get_v3(JOINT, cyl, "get_Position", p)) cyl_in_gun = ig.p + rotate(ig.q, p);
    if (lid != nullptr && get_v3(JOINT, lid, "get_Position", p)) lid_in_gun = ig.p + rotate(ig.q, p);
    const Quat lturn = g_have_left_turn ? g_grip_left_turn : qnorm(qmul(ig.q, lt0.q));
    g_left_in_gun = {cyl_in_gun + g_left_off, lturn};
    g_right_dock_in_gun = {lid_in_gun + g_right_off, g_right_in_gun.q};
    g_left_from = lt0;
    g_left_t0 = now_s();
    g_gun_s = g0;
    g_smooth_t = -1.0f;
    g_weapon_tf = s.weapon_tf;
    g_parented = call_ptr(s.weapon_tf, "get_Parent") != nullptr;
    if (!get_v3(XFORM, s.weapon_tf, "get_LocalPosition", g_local_p) || !get_q(XFORM, s.weapon_tf, "get_LocalRotation", g_local_q)) g_parented = false;
    g_rounds = 0;
    g_rdock = false;
    g_ru = g_ru0 = 0.0f;
    g_last_right = rt0;
    g_praydog_frame = -1.0f;
    LOGI("%s gate: LG with the cover open: the Wolfsbane held by the left hand, the right hand free (drum %s at %.3f %.3f %.3f, cover %s at %.3f %.3f %.3f in the gun's frame; left turn %s)",
         TAG, cyl != nullptr ? "joint" : "GUESS", cyl_in_gun.x, cyl_in_gun.y, cyl_in_gun.z, lid != nullptr ? "joint" : "GUESS",
         lid_in_gun.x, lid_in_gun.y, lid_in_gun.z, g_have_left_turn ? "from the last two-handed grip" : "as the hand was");
    return true;
}

void to_return(const char* why) {
    g_phase = Phase::RETURN;
    g_t0 = now_s();
    g_ret_from = g_last_right;
    g_rdock = false;
    if (g_rounds > 0) LOGI("%s gate: %d round(s) left in the right hand go back in the pouch", TAG, g_rounds);
    g_rounds = 0;
    LOGI("%s gate: %s: the right hand goes back on the grip, then the thumb shuts the cover", TAG, why);
}

void to_handover(float sec, bool keep_left, const char* why) {
    g_phase = Phase::HANDOVER;
    g_t0 = now_s();
    g_ho_sec = sec;
    g_ho_right = g_last_right;
    g_ho_gun = g_gun_now;
    g_ho_left = keep_left;
    g_rdock = false;
    if (g_rounds > 0) LOGI("%s gate: %d round(s) in the right hand go back in the pouch", TAG, g_rounds);
    g_rounds = 0;
    LOGI("%s gate: %s: the gun eased back onto the right hand over %.2f s", TAG, why, sec);
}

void glide_right(bool dock) {
    if (dock == g_rdock) return;
    g_rdock = dock;
    g_ru0 = g_ru;
    g_rt0 = now_s();
}

void right_hand() {   // HELD: the right hand's jobs, the drum's turn
    const bool rg = bridge::held(bridge::S_RGRIP);
    if (bridge::pressed(bridge::S_LTRIG)) {
        if (g_need_turn) {
            g_need_turn = false;
            ++g_turns;
            const bool casing = breech::drop_casing();
            bridge::sfx(casing ? bridge::SFX_MAG_OUT : bridge::SFX_SLIDE_FORWARD);
            bridge::rumble(bridge::LEFT, GATE_BUZZ_AMP, GATE_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s gate: LT: the drum turned one chamber%s (%d spent left)", TAG, casing ? ", a spent casing falls out" : "", breech::spent_casings());
        } else {
            LOGI("%s gate: LT: the drum turns only after a round has gone in", TAG);
        }
    }
    if (bridge::pressed(bridge::S_RGRIP) && g_rounds == 0 && !g_rdock && reload::pouch_dist(bridge::RIGHT) < POUCH_ENTER_M) {
        const int free = breech::free_chambers(), carried = player::unlimited() ? free : std::max(0, player::reserve());
        const int n = std::min(free, carried);
        if (n <= 0) {
            bridge::rumble(bridge::RIGHT, RELOAD_DENY_BUZZ_AMP, RELOAD_DENY_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s gate: RG at the pouch: nothing to take (%d free chamber(s), %d carried)", TAG, free, carried);
        } else {
            g_rounds = n;
            bridge::rumble(bridge::RIGHT, RELOAD_GRAB_BUZZ_AMP, RELOAD_GRAB_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s gate: RG at the pouch: %d round(s) in the right hand (%d free, %d carried); RG held to the cover docks it", TAG, n, free, carried);
        }
    }
    if (!rg && g_rounds > 0) {
        LOGI("%s gate: RG let go: the %d round(s) go back in the pouch", TAG, g_rounds);
        g_rounds = 0;
    }
    if (!rg && g_rdock) glide_right(false);
    if (!g_rdock && rg && g_rounds > 0 && g_now_ok) {
        Vec3 rw;
        const float d = bridge::room_to_world(bridge::hand_pos(bridge::RIGHT), rw) ? dist(rw, mul(g_gun_now, g_right_dock_in_gun).p) : 99.0f;
        if (d < GATE_DOCK_M) {
            glide_right(true);
            bridge::rumble(bridge::RIGHT, GATE_BUZZ_AMP, GATE_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s gate: the right hand docks at the cover (%.3f m): RT puts a round in%s", TAG, d, g_need_turn ? " once LT has turned the drum" : "");
        }
    }
    const float k = std::fmin(1.0f, (now_s() - g_rt0) / GATE_GLIDE_SEC);
    g_ru = g_rdock ? g_ru0 + (1.0f - g_ru0) * ease(k) : g_ru0 * (1.0f - ease(k));
    if (!g_rdock || !bridge::pressed(bridge::S_RTRIG)) return;
    if (g_need_turn) {
        bridge::rumble(bridge::RIGHT, RELOAD_DENY_BUZZ_AMP, RELOAD_DENY_BUZZ_SEC, RELOAD_BUZZ_HZ);
        LOGI("%s gate: RT at the cover: turn the drum with LT first", TAG);
        return;
    }
    if (!reload::insert_direct()) { LOGI("%s gate: RT at the cover: no round went in", TAG); return; }
    --g_rounds;
    g_need_turn = true;
    bridge::rumble(bridge::RIGHT, RELOAD_INSERT_BUZZ_AMP, RELOAD_INSERT_BUZZ_SEC, RELOAD_BUZZ_HZ);
    LOGI("%s gate: a round in (loaded %d, %d left in the right hand)", TAG, player::loaded(), g_rounds);
    if (g_rounds <= 0 || breech::free_chambers() <= 0) to_return(breech::free_chambers() <= 0 ? "the drum is full" : "the right hand is empty");
}

void poses() {   // this frame's gun and hands, from the left controller read once
    g_now_ok = false;
    const float now = now_s();
    if (g_phase == Phase::STAY) {
        g_now_ok = tf_pose(g_weapon_tf, g_gun_now);
        return;
    }
    Pose lc{};
    if (g_phase == Phase::OFF || !left_controller(lc)) return;
    const float dt = g_smooth_t < 0.0f ? 0.0f : std::fmin(0.1f, now - g_smooth_t);
    g_smooth_t = now;
    if (g_phase == Phase::HANDOVER) {
        g_gun_now = blend(g_ho_gun, mul(g_praydog, g_gun_in_right), ease((now - g_t0) / g_ho_sec));
    } else {
        g_gun_s = blend(g_gun_s, mul(lc, g_gun_k), 1.0f - std::exp(-dt / RIGHT_RACK_LOCK_FOLLOW_SEC));
        g_gun_now = g_gun_s;
    }
    g_now_ok = true;
}

void write_gun() {
    if ((g_phase != Phase::HELD && g_phase != Phase::RETURN && g_phase != Phase::HANDOVER) || !g_now_ok || g_weapon_tf == nullptr ||
        player::now().weapon_tf != g_weapon_tf) return;
    player::set_pose(g_weapon_tf, g_gun_now.p, g_gun_now.q);
}

void turn_drum() {   // the drum drawn turning one chamber per LT, while the cover is open
    if (!here() || !breech::is_open()) return;
    if (g_cyl == nullptr && player::now().weapon_tf != nullptr) {
        g_cyl = joint_by_name(player::now().weapon_tf, L"Cylinder");
        g_cyl_ok = g_cyl != nullptr && get_q(JOINT, g_cyl, "get_LocalRotation", g_cyl_rest);
        LOGI("%s gate: drum joint %s", TAG, g_cyl_ok ? "Cylinder found: it turns with LT" : "NOT found: no visible turn");
    }
    if (!g_cyl_ok) return;
    const float now = now_s(), dt = g_cyl_t < 0.0f ? 0.0f : std::fmin(0.1f, now - g_cyl_t);
    g_cyl_t = now;
    const float want = (float)g_turns, step = GATE_CYL_TURN_SEC > 0.0f ? dt / GATE_CYL_TURN_SEC : 1.0f;
    g_cyl_draw = want > g_cyl_draw ? std::fmin(want, g_cyl_draw + step) : want;
    const int cap = player::capacity() > 0 ? player::capacity() : 6;
    Quat q = qnorm(qmul(g_cyl_rest, axis_turn(g_cyl_axis, 360.0f / (float)cap * g_cyl_draw)));
    set_any(JOINT, g_cyl, "set_LocalRotation", &q);
}
} // namespace

bool here() { return breech::cover_gun(); }
bool holding() { return g_phase == Phase::HELD || g_phase == Phase::RETURN; }
bool owns_left() { return g_phase == Phase::HELD || g_phase == Phase::RETURN || g_phase == Phase::STAY || (g_phase == Phase::HANDOVER && g_ho_left); }

void tune(const Vec3& left, const Vec3& right, const Vec3& cyl_axis) { g_left_off = left; g_right_off = right; g_cyl_axis = cyl_axis; }

void close_request(const char* why) { if (g_phase == Phase::HELD) to_return(why); }

void abort(const char* why) {
    if (g_phase == Phase::OFF) return;
    if (g_phase != Phase::STAY) put_local_back(why);
    LOGI("%s gate: off (%s)", TAG, why);
    g_phase = Phase::OFF;
    g_rounds = 0;
    g_rdock = false;
    g_weapon_tf = nullptr;
}

void frame() {
    const auto& s = player::now();
    const std::string id = weapons::canonical(s.weapon_id);
    if (id != g_id) { abort("the gun changed"); g_id = id; g_cyl = nullptr; g_cyl_ok = false; g_have_left_turn = false; g_was_open = false; }
    if (g_phase != Phase::OFF && s.weapon_tf != g_weapon_tf) abort("the gun changed");
    if (!here()) { bridge::put(bridge::S_GATE_HOLD, 0.0f); return; }
    const bool play = bridge::flag(bridge::S_CAN_USE_HANDS) && !bridge::flag(bridge::S_CUTSCENE);
    const bool lg = bridge::held(bridge::S_LGRIP);
    const bool open = breech::is_open();
    if (open && !g_was_open) { g_need_turn = false; g_turns = 0; g_cyl_draw = 0.0f; g_cyl_t = -1.0f; }
    g_was_open = open;
    if (g_phase == Phase::OFF && bridge::flag(bridge::S_GRIPPING_WEAPON)) {   // remember how the left hand sits on the gun
        Pose g{}, l{};
        if (tf_pose(s.weapon_tf, g) && s.ik_left != nullptr && tf_pose(target_of(s.ik_left), l)) { g_grip_left_turn = qnorm(qmul(qinv(g.q), l.q)); g_have_left_turn = true; }
    }
    const float now = now_s();
    switch (g_phase) {
    case Phase::OFF:
    case Phase::STAY: {
        if (g_phase == Phase::STAY && (!lg || !play)) { LOGI("%s gate: LG let go: the left hand leaves the drum", TAG); g_phase = Phase::OFF; g_weapon_tf = nullptr; break; }
        if (!open || !play || !lg) break;
        // 2026-11-01 23:0x (Tefa: "when the guard is open, LG anywhere will smoothly but quickly take the left hand to the weapon
        // and freeze it in place and release the right hand"): any fresh LG, wherever the left hand is
        const bool fresh = bridge::pressed(bridge::S_LGRIP) || bridge::flag(bridge::S_GRIPPING_WEAPON) || g_phase == Phase::STAY;
        if (!fresh) break;
        if (!take()) break;
        g_phase = Phase::HELD;
        bridge::rumble(bridge::LEFT, GATE_BUZZ_AMP, GATE_BUZZ_SEC, RELOAD_BUZZ_HZ);
        break;
    }
    case Phase::HELD:
        if (!lg || !play) to_handover(RIGHT_RACK_DROP_SEC, false, "LG let go: the cover stays open");
        else if (!open) to_handover(RIGHT_RACK_HANDOVER_SEC, true, "the cover shut");
        else right_hand();
        break;
    case Phase::RETURN:
        if (now - g_t0 >= GATE_RETURN_SEC) {
            breech::close_cover("the thumb shuts the cover");
            to_handover(RIGHT_RACK_HANDOVER_SEC, lg && play, "the right hand on the grip");
        }
        break;
    case Phase::HANDOVER:
        if (now - g_t0 >= g_ho_sec) {
            put_local_back("handed back");
            if (g_ho_left && lg && play && !breech::is_open()) {
                g_phase = Phase::STAY;
                LOGI("%s gate: the cover shut: the right hand steers, the left hand stays on the drum until LG is let go", TAG);
            } else {
                g_phase = Phase::OFF;
                g_weapon_tf = nullptr;
            }
        }
        break;
    }
    poses();
    bridge::put(bridge::S_GATE_HOLD, holding() ? 1.0f : 0.0f);
}

void on_ik(MO* ik) {
    if (g_phase == Phase::OFF || !g_now_ok) return;
    const auto& s = player::now();
    const float now = now_s();
    if (ik == s.ik_right) {
        if (g_phase == Phase::STAY) return;   // the game's grip: the right hand steers
        MO* t = target_of(ik);
        Pose cur{};
        if (!tf_pose(t, cur)) return;
        const float frame = bridge::view(bridge::S_FRAME);
        if (frame != g_praydog_frame) { g_praydog_frame = frame; g_praydog = cur; }   // the first solve: as the VR layer asked
        Pose want = g_praydog;
        if (g_phase == Phase::HELD) {
            if (g_ru <= 0.0f) { g_last_right = cur; return; }   // free: the right hand follows its controller
            want = blend(g_praydog, mul(g_gun_now, g_right_dock_in_gun), g_ru);
        } else if (g_phase == Phase::RETURN) {
            want = blend(g_ret_from, mul(g_gun_now, g_right_in_gun), ease((now - g_t0) / GATE_RETURN_SEC));
        } else if (g_phase == Phase::HANDOVER) {
            want = blend(g_ho_right, g_praydog, ease((now - g_t0) / g_ho_sec));
        }
        player::set_pose(t, want.p, want.q);
        g_last_right = want;
    } else if (ik == s.ik_left) {
        if (g_phase == Phase::HANDOVER && !g_ho_left) return;
        Pose want = mul(g_gun_now, g_left_in_gun);
        const float k = (now - g_left_t0) / GATE_GLIDE_SEC;
        if (g_phase == Phase::HELD && k < 1.0f) want = blend(g_left_from, want, ease(k));
        player::set_pose(target_of(ik), want.p, want.q);
    }
}

void late_point() { write_gun(); turn_drum(); }

} // namespace vn::gate
