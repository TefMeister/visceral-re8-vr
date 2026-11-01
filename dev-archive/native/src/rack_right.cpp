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

// ON: the gun on the left controller, the right hand gliding onto / riding the bolt. BACK: the right hand gliding back to
// the grip, the gun still on the left. HANDOVER: the gun back on the right hand, its target eased to the controller's.
enum class Phase { OFF, ON, BACK, HANDOVER };
const char* phase_name(Phase p) { return p == Phase::ON ? "on the bolt" : p == Phase::BACK ? "back to the grip" : p == Phase::HANDOVER ? "handed back" : "off"; }
Phase g_phase = Phase::OFF;
float g_t0 = 0.0f;            // the current glide's start
float g_u = 0.0f, g_u0 = 0.0f;   // 0 = the right hand on the grip, 1 = on the bolt; g_u0 at the glide's start

MO* g_weapon_tf = nullptr;    // the gun this take holds (its transform)
Pose g_gun_k{}, g_right_k{}, g_left_k{};   // the gun, the right and the left IK targets, in the left controller's frame
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
        LOGW("%s rack_right: RG for the bolt, but something could not be read (left controller / gun / hand targets / bolt joint): not taken", TAG);
        return false;
    }
    const Pose ilc = inverse(lc);
    g_gun_k = mul(ilc, g0);
    g_right_k = mul(ilc, rt0);
    g_left_k = mul(ilc, lt0);
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
    LOGI("%s rack_right: RIGHT hand takes the bolt: gun %s (local %.3f %.3f %.3f); bolt %.3f m from the right hand's target, %.3f m from the left's; palm offset %.3f m",
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
    if (g_phase == Phase::ON || g_phase == Phase::BACK) check_drift();

    switch (g_phase) {
    case Phase::OFF:
        if (!bridge::pressed(bridge::S_RGRIP) || !lg || !lt || !play || !bridge::flag(bridge::S_GRIPPING_WEAPON)) break;
        if (std::strcmp(rack::part_name(), "bolt") != 0) break;   // a bolt gun only (the rifle)
        if (!rack::bolt_may_take() || reload::session_active() || reload::hand_on_mag() || reload::mag_out()) {
            if (now_s() - g_why_t > 1.0f) {
                g_why_t = now_s();
                LOGI("%s rack_right: RG with the left hand on the front and LT held, but the bolt is not free now (%s)", TAG,
                     reload::mag_out() || reload::session_active() || reload::hand_on_mag() ? "a magazine is being handled" : "no rack due, or the left hand has it");
            }
            break;
        }
        if (!take()) break;
        rack::right_take();
        g_phase = Phase::ON;
        g_u = 0.0f;
        glide_start();
        bridge::rumble(bridge::RIGHT, RIGHT_RACK_BUZZ_AMP, RACK_BUZZ_SEC, RELOAD_BUZZ_HZ);
        break;
    case Phase::ON:
        g_u = g_u0 + (1.0f - g_u0) * ease(glide_k());
        if (!rg) to_back("RG let go");
        else if (!lg) to_back("LG let go: the left hand no longer holds the gun");
        else if (!play) to_back("cutscene / hands not free");
        else if (!rack::right_on()) to_back("the rack let go of it");
        break;
    case Phase::BACK:
        g_u = g_u0 * (1.0f - ease(glide_k()));
        if (glide_k() >= 1.0f) {
            put_local_back("RG let go");
            g_phase = Phase::HANDOVER;
            g_t0 = now_s();
        }
        break;
    case Phase::HANDOVER:
        if (now_s() - g_t0 >= RIGHT_RACK_HANDOVER_SEC) to_off();
        break;
    }

    // this frame's poses, from the left controller read once, so the hands and the gun agree with each other
    g_now_ok = false;
    Pose lc{};
    if (g_phase != Phase::OFF && left_controller(lc)) {
        g_gun_now = mul(lc, g_gun_k);
        g_left_now = mul(lc, g_left_k);
        g_grip_now = mul(lc, g_right_k);
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
        const Pose want = g_phase == Phase::HANDOVER ? blend(g_grip_now, g_praydog, ease((now_s() - g_t0) / RIGHT_RACK_HANDOVER_SEC))
                                                     : blend(g_grip_now, bolt_hand(), g_u);
        player::set_pose(t, want.p, want.q);
    } else if (ik == s.ik_left && g_phase != Phase::HANDOVER) {
        player::set_pose(target_of(ik), g_left_now.p, g_left_now.q);   // the left hand stays on the front, riding its controller
    }
}

void write_gun() {
    if (!active() || !g_now_ok || g_weapon_tf == nullptr || player::now().weapon_tf != g_weapon_tf) return;
    player::set_pose(g_weapon_tf, g_gun_now.p, g_gun_now.q);
    g_put = g_gun_now;
    g_written = true;
}

void late_point() { write_gun(); }
void begin_render_point() { write_gun(); }

} // namespace vn::rack_right
