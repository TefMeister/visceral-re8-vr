// rack_right.cpp -- see rack_right.h
#include "rack_right.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "rack.h"
#include "reload.h"
#include "settings.h"

#include <cstring>

namespace vn::rack_right {

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
bool tf_pose(MO* tf, Pose& out) { return player::get_pose(tf, out.p, out.q); }

// 2026-11-01 (Tefa, third pass: "LG + LT held on the rifle front should not freeze the weapon, just make it ready for RG to be
// usable, then, whenever RG is pressed and held, the LG+LT combo freezes the weapon ... when LT is let go mid way of RG racking
// the bolt, gun must stay frozen until racking is complete. if LG is let go in the middle of racking, rifle must quickly but
// smoothly go back to right hand with the bolt in position it was when racking got interrupted and can be continued with
// LG+LT"). So: ON = RG pressed with LG + LT on the front: the gun trails the left controller, the right hand gliding onto /
// riding the bolt. BACK: RG let go (or LT let go with no rack under way): the right hand glides back to the grip.
// HANDOVER: the gun and the right hand eased back onto the right controller (quick when LG was let go).
enum class Phase { OFF, ON, BACK, HANDOVER };
const char* phase_name(Phase p) { return p == Phase::ON ? "on the bolt" : p == Phase::BACK ? "back to the grip" : p == Phase::HANDOVER ? "handed back" : "off"; }
Phase g_phase = Phase::OFF;
float g_t0 = 0.0f;            // the current glide's start
float g_u = 0.0f, g_u0 = 0.0f;   // 0 = the right hand on the grip, 1 = on the bolt; g_u0 at the glide's start

MO* g_weapon_tf = nullptr;    // the gun this take holds (its transform)
Pose g_gun_k{};               // the gun in the left controller's frame at the take
Pose g_right_in_gun{}, g_left_in_gun{};   // both hands' IK targets in the gun's frame: they stay docked on it
Pose g_gun_s{};               // the gun as drawn: it trails the left controller slowly (Tefa: "not freeze in place, but very slow to move")
float g_smooth_t = -1.0f;
Quat g_grip_turn{0, 0, 0, 1}; // the right hand's turn in the gun's frame (as it holds the grip): kept on the bolt
Pose g_bolt_rest{};           // the bolt joint at rest, in the gun's frame
Vec3 g_palm{};                // R_Hand -> R_Palm in the hand's frame (zero: the wrist goes on the bolt)
bool g_parented = false;      // the gun's transform has a parent: its local pose is put back after
Vec3 g_local_p{};
Quat g_local_q{0, 0, 0, 1};

Pose g_gun_now{};             // this frame's gun, from the left controller read once in frame()
Pose g_left_now{}, g_grip_now{};
bool g_now_ok = false;
float g_praydog_frame = -1.0f;
Pose g_praydog{};             // the right target as the VR layer asked it, at the frame's first solve (the handover's end)
Pose g_gun_in_right{};        // the gun in the right IK target's frame at the take: where it hangs once handed back
Pose g_last_right{};
Pose g_left_grip{};           // 2026-11-01: the left target the grip asks for during a hand-back (first solve of the frame)
float g_left_frame = -1.0f;          // the right target we wrote last: where a handover starts
float g_ho_sec = 0.3f;        // this handover's length
Pose g_ho_right{}, g_ho_gun{}; // the right target and the gun when it began
bool g_ho_left = false;       // LG still held: the left hand rides the gun through it
bool g_lt_told = false;

bool g_written = false;       // the gun was written last frame: g_put is where
Pose g_put{};
float g_drift_max = 0.0f, g_drift_log_t = 0.0f;
int g_drift_n = 0;
float g_why_t = -10.0f;

bool left_controller(Pose& out) {
    return bridge::room_to_world(bridge::hand_pos(bridge::LEFT), out.p) && bridge::room_rot_to_world(bridge::view_quat(bridge::S_LROT), out.q);
}
float glide_k() { return std::fmin(1.0f, (now_s() - g_t0) / RIGHT_RACK_GLIDE_SEC); }
void glide_start() { g_u0 = g_u; g_t0 = now_s(); }   // a glide on or off the bolt starts from where the hand is now

// the right hand's target on the bolt this frame: the palm on the bolt joint (plus the settings' nudge), the hand's turn as
// it held the grip, both riding the bolt's travel and its turn about its own axis
Pose bolt_hand() {
    const Pose& g = g_gun_now;
    const float h = rack::bolt_half_turn_rad();
    const Quat zr{0, 0, std::sin(h), std::cos(h)};
    const Vec3 bolt_p = g.p + rotate(g.q, g_bolt_rest.p + Vec3{0, 0, rack::bolt_dz()});
    const Quat jf = qnorm(qmul(g.q, g_bolt_rest.q));            // the bolt's rest frame in the world
    const Quat turn = qnorm(qmul(qmul(jf, zr), qinv(jf)));       // its turn now, about its own Z
    const Quat hand0 = qnorm(qmul(g.q, g_grip_turn));
    const Vec3 offs = rotate(g.q, Vec3{RIGHT_BOLT_HAND_X_M, RIGHT_BOLT_HAND_Y_M, RIGHT_BOLT_HAND_Z_M}) - rotate(hand0, g_palm);
    return {bolt_p + rotate(turn, offs), qnorm(qmul(turn, hand0))};
}

void put_local_back(const char* why) {
    if (g_weapon_tf == nullptr) return;
    if (g_parented) {
        set_any(XFORM, g_weapon_tf, "set_LocalPosition", &g_local_p);
        set_any(XFORM, g_weapon_tf, "set_LocalRotation", &g_local_q);
    }
    LOGI("%s rack_right: the gun back on the right hand (%s)%s; drawn off where it was put: worst %.1f cm over %d frames", TAG, why,
         g_parented ? ", its own local pose put back" : " (it has no parent: the game places it)", g_drift_max * 100.0f, g_drift_n);
    g_written = false;
}

bool take() {
    const auto& s = player::now();
    Pose lc{}, g0{}, rt0{}, lt0{};
    MO* bolt = (MO*)rack::slide_joint();
    Vec3 jp{};
    Quat jq{};
    if (!left_controller(lc) || !tf_pose(s.weapon_tf, g0) || s.ik_right == nullptr || s.ik_left == nullptr ||
        !tf_pose(target_of(s.ik_right), rt0) || !tf_pose(target_of(s.ik_left), lt0) || bolt == nullptr ||
        !get_v3(JOINT, bolt, "get_Position", jp) || !get_q(JOINT, bolt, "get_Rotation", jq)) {
        LOGW("%s rack_right: RG with LG + LT on the front, but something could not be read (left controller / gun / hand targets / bolt joint): not taken", TAG);
        return false;
    }
    const Pose ilc = inverse(lc);
    g_gun_k = mul(ilc, g0);
    const Pose ig = inverse(g0);
    g_right_in_gun = mul(ig, rt0);
    g_left_in_gun = mul(ig, lt0);
    g_gun_in_right = mul(inverse(rt0), g0);
    g_last_right = rt0;
    g_gun_s = g0;                 // it starts where it is drawn: no jump at the take
    g_smooth_t = -1.0f;
    g_grip_turn = qnorm(qmul(qinv(g0.q), rt0.q));
    Pose bg = mul(inverse(g0), Pose{jp, qnorm(jq)});   // the bolt in the gun's frame, then back to its rest
    bg.p = bg.p - Vec3{0, 0, rack::bolt_dz()};
    const float h = rack::bolt_half_turn_rad();
    bg.q = qnorm(qmul(bg.q, qinv(Quat{0, 0, std::sin(h), std::cos(h)})));
    g_bolt_rest = bg;
    g_palm = Vec3{0, 0, 0};
    if (RIGHT_PALM_ON_BOLT) {
        MO* hand = joint_by_name(s.tf, L"R_Hand");
        MO* palm = joint_by_name(s.tf, L"R_Palm");
        Vec3 hp{}, pp{};
        Quat hq{};
        if (hand != nullptr && palm != nullptr && get_v3(JOINT, hand, "get_Position", hp) && get_v3(JOINT, palm, "get_Position", pp) &&
            get_q(JOINT, hand, "get_Rotation", hq))
            g_palm = rotate(qinv(qnorm(hq)), pp - hp);
    }
    g_weapon_tf = s.weapon_tf;
    g_parented = call_ptr(s.weapon_tf, "get_Parent") != nullptr;
    if (!get_v3(XFORM, s.weapon_tf, "get_LocalPosition", g_local_p) || !get_q(XFORM, s.weapon_tf, "get_LocalRotation", g_local_q)) g_parented = false;
    g_written = false;
    g_drift_max = 0.0f;
    g_drift_n = 0;
    g_drift_log_t = now_s();
    g_praydog_frame = -1.0f;
    LOGI("%s rack_right: RG with LG + LT on the front: the rifle held by the left hand, the right hand to the bolt: gun %s (local %.3f %.3f %.3f); bolt %.3f m from the right hand's target, %.3f m from the left's; palm offset %.3f m",
         TAG, g_parented ? "parented" : "NOT parented", g_local_p.x, g_local_p.y, g_local_p.z, dist(jp, rt0.p), dist(jp, lt0.p),
         std::sqrt(g_palm.x * g_palm.x + g_palm.y * g_palm.y + g_palm.z * g_palm.z));
    return true;
}

void to_back(const char* why) {
    rack::right_off(why);
    g_phase = Phase::BACK;
    glide_start();
    LOGI("%s rack_right: %s: the right hand goes back to the grip", TAG, why);
}

void to_handover(float sec, bool keep_left, const char* why) {
    rack::right_off(why);
    g_ho_sec = sec;
    g_ho_right = g_last_right;
    g_ho_gun = g_gun_s;
    g_ho_left = keep_left;
    g_phase = Phase::HANDOVER;
    g_t0 = now_s();
    LOGI("%s rack_right: %s: the rifle eased back onto the right hand over %.2f s (bolt left at travel %.2f)", TAG, why, sec, rack::travel());
}

void to_off() {
    g_phase = Phase::OFF;
    g_u = 0.0f;
    g_weapon_tf = nullptr;
}

// where the drawn gun is against where it was put (read at the frame's start = what was drawn last frame)
void check_drift() {
    if (!g_written || g_weapon_tf == nullptr) return;
    Pose drawn{};
    if (!tf_pose(g_weapon_tf, drawn)) return;
    const float d = dist(drawn.p, g_put.p);
    g_drift_max = std::fmax(g_drift_max, d);
    ++g_drift_n;
    if (now_s() - g_drift_log_t >= RIGHT_RACK_LOG_SEC) {
        g_drift_log_t = now_s();
        LOGI("%s rack_right: gun held by the left hand (%s): drawn %.1f cm from where it was put (worst %.1f), bolt step travel %.2f", TAG,
             phase_name(g_phase), d * 100.0f, g_drift_max * 100.0f, rack::travel());
    }
}
} // namespace

bool active() { return g_phase == Phase::ON || g_phase == Phase::BACK; }
bool locked() { return g_phase != Phase::OFF; }   // the gun is ours (held by the left hand, or being handed back)

void abort(const char* why) {
    if (g_phase == Phase::OFF) return;
    rack::right_off(why);
    if (g_phase != Phase::HANDOVER) put_local_back(why);
    to_off();
}

void frame(bool play, bool lg, bool lt) {
    const auto& s = player::now();
    const bool rg = bridge::held(bridge::S_RGRIP);
    if (g_phase != Phase::OFF && s.weapon_tf != g_weapon_tf) { abort("the gun changed"); return; }
    if (active()) check_drift();

    const bool front = lg && bridge::flag(bridge::S_GRIPPING_WEAPON) && std::strcmp(rack::part_name(), "bolt") == 0;   // a bolt gun only
    const bool busy = reload::mag_out() || reload::session_active() || reload::hand_on_mag() || rack::active();
    switch (g_phase) {
    case Phase::OFF:
        if (!bridge::pressed(bridge::S_RGRIP) || !front || !lt || !play || busy) break;   // LG + LT on the front only make RG ready
        if (!rack::bolt_free()) {
            if (now_s() - g_why_t > 1.0f) { g_why_t = now_s(); LOGI("%s rack_right: RG with LG + LT on the front, but the bolt is not free (the left hand has it?)", TAG); }
            break;
        }
        if (!take()) break;
        rack::right_take();
        g_phase = Phase::ON;
        g_u = 0.0f;
        g_lt_told = false;
        glide_start();
        bridge::rumble(bridge::RIGHT, RIGHT_RACK_BUZZ_AMP, RACK_BUZZ_SEC, RELOAD_BUZZ_HZ);
        break;
    case Phase::ON:
        g_u = g_u0 + (1.0f - g_u0) * ease(glide_k());
        if (!lg) to_handover(RIGHT_RACK_DROP_SEC, false, "LG let go mid-rack: the bolt stays where it is");
        else if (!play) to_handover(RIGHT_RACK_DROP_SEC, false, "cutscene / hands not free");
        else if (!rg) to_back("RG let go");
        else if (!rack::right_on()) to_back("the rack let go of it");
        else if (!lt && !rack::right_busy()) to_back("LT let go with no rack under way");
        else if (!lt && !g_lt_told) { g_lt_told = true; LOGI("%s rack_right: LT let go mid-rack: the rifle stays held until the bolt is done", TAG); }
        break;
    case Phase::BACK:
        g_u = g_u0 * (1.0f - ease(glide_k()));
        if (!lg || !play) to_handover(RIGHT_RACK_DROP_SEC, false, "LG let go on the way back");
        else if (glide_k() >= 1.0f) to_handover(RIGHT_RACK_HANDOVER_SEC, true, "the right hand back on the grip");
        break;
    case Phase::HANDOVER:
        if (now_s() - g_t0 >= g_ho_sec) { put_local_back("handed back"); to_off(); }
        break;
    }

    // this frame's poses, from the left controller read once, so the hands and the gun agree with each other
    g_now_ok = false;
    Pose lc{};
    if (g_phase != Phase::OFF && left_controller(lc)) {
        // 2026-11-01 (Tefa: "if it can be done then not freeze in place, but very slow to move while. why i'm asking is because i
        // need the left hand docked on the front end at all times for it to look good"): the gun eases toward where the left
        // controller would carry it, and BOTH hands are drawn on the gun (the left on the front, the right on the grip or the
        // bolt), so the left hand never leaves the front however the controller moves
        const float now = now_s();
        const float dt = g_smooth_t < 0.0f ? 0.0f : std::fmin(0.1f, now - g_smooth_t);
        g_smooth_t = now;
        if (g_phase == Phase::HANDOVER) {   // from where it was held to where the right hand carries it (the VR layer's target)
            g_gun_now = blend(g_ho_gun, mul(g_praydog, g_gun_in_right), ease((now - g_t0) / g_ho_sec));
        } else {
            g_gun_s = blend(g_gun_s, mul(lc, g_gun_k), 1.0f - std::exp(-dt / RIGHT_RACK_LOCK_FOLLOW_SEC));
            g_gun_now = g_gun_s;
        }
        g_left_now = mul(g_gun_now, g_left_in_gun);
        g_grip_now = mul(g_gun_now, g_right_in_gun);
        g_now_ok = true;
    }
}

void on_ik(MO* ik) {
    if (g_phase == Phase::OFF || !g_now_ok) return;
    const auto& s = player::now();
    if (ik == s.ik_right) {
        MO* t = target_of(ik);
        Pose cur{};
        if (!tf_pose(t, cur)) return;
        const float frame = bridge::view(bridge::S_FRAME);
        if (frame != g_praydog_frame) { g_praydog_frame = frame; g_praydog = cur; }   // the first solve: as the VR layer asked
        const Pose want = g_phase == Phase::HANDOVER ? blend(g_ho_right, g_praydog, ease((now_s() - g_t0) / g_ho_sec))
                                                     : blend(g_grip_now, bolt_hand(), g_u);
        player::set_pose(t, want.p, want.q);
        g_last_right = want;
    } else if (ik == s.ik_left && (g_phase != Phase::HANDOVER || g_ho_left)) {
        MO* t = target_of(ik);
        if (g_phase == Phase::HANDOVER) {
            // 2026-11-01: eased from riding the gun to where the grip asks for it (the left target as the writers before this
            // one left it, read at the frame's first solve), so the hand-back never ends in a snap: measured on the simulator,
            // the left hand turned 175 deg in one frame as the hand-back ended [verified-live 2026-11-01, n=1]
            Pose cur{};
            const float frame = bridge::view(bridge::S_FRAME);
            if (frame != g_left_frame && tf_pose(t, cur)) { g_left_frame = frame; g_left_grip = cur; }
            const Pose want = blend(g_left_now, g_left_grip, ease((now_s() - g_t0) / g_ho_sec));
            player::set_pose(t, want.p, want.q);
            return;
        }
        player::set_pose(t, g_left_now.p, g_left_now.q);   // the left hand stays docked on the front of the gun
    }
}

void write_gun() {
    if (!locked() || !g_now_ok || g_weapon_tf == nullptr || player::now().weapon_tf != g_weapon_tf) return;
    player::set_pose(g_weapon_tf, g_gun_now.p, g_gun_now.q);
    g_put = g_gun_now;
    g_written = true;
}

void late_point() { write_gun(); }
void render_point() { write_gun(); }
void begin_render_point() { write_gun(); }

} // namespace vn::rack_right
