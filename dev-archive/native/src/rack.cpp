// rack.cpp -- see rack.h. Gesture and timings from Visceral RE2's rack.cpp via RE7; the grab test is in the room, from
// the controllers (RE2 b162's pump test, used for every gun here), and the hand's place on the gun is captured from the
// left IK target at the moment it takes hold.
#include "rack.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "reload.h"
#include "settings.h"
#include "weapons.h"

#include <windows.h>
#include <mmsystem.h>

#include <filesystem>
#include <string>

namespace vn::rack {

using namespace joints;
using namespace vn::settings;

namespace {
const weapons::Weapon* g_w = nullptr;
std::string g_id;
MO* g_joint = nullptr;
Vec3 g_rest{};
bool g_have_rest = false;

bool g_needed = false, g_parked = false, g_hand_on = false, g_armed = false, g_pulled = false, g_spent = false;
bool g_hold_closed = false;
int g_auto = 0;               // 2 = the pump handle is returning by itself
float g_auto_t0 = 0.0f;
float g_travel = 0.0f, g_base = 0.0f, g_max_pull = 0.0f;
Vec3 g_axis{0, 0, -1};        // the gun's forward in the room, frozen when the pull is armed
int g_last_loaded = -1;
int g_log_near = 0;

bool g_capture = false;       // take the hand's turn (and, with no slide joint, its place) at the next left-arm solve
// the slide joint relative to the right hand target, measured after each frame's animation (late_point)
bool g_slide_ok = false;
Vec3 g_slide_pos{};
Quat g_slide_gun{0, 0, 0, 1};
float g_z_anim = 0.0f;
bool g_rel_ok = false;
Vec3 g_rel_pos{};
Quat g_rel_rot{0, 0, 0, 1};
Quat g_rest_rot{0, 0, 0, 1};

// the bolt cycle: 0 locked, 1 turned up, 2 pulled back (clicked), 3 pushed home (still up); turned down from 3 = done
int g_bstate = 0;
float g_turn = 0.0f;          // 0 = down / locked, 1 = up
float g_dy0 = 0.0f;           // left - right height that counts as "turn 0" (set when the hand takes hold)

bool pose_lock() { return bridge::flag(bridge::S_POSE_LOCK); }
bool pump() { return g_w != nullptr && g_w->pump; }
bool bolt() { return g_w != nullptr && g_w->bolt; }
bool rackable() { return g_w != nullptr && (g_w->rack || g_w->pump); }
const char* part() { return pump() ? "pump" : bolt() ? "bolt" : "slide"; }
float z_now() { return g_rest.z + (pump() ? PUMP_BACK_M : SLIDE_BACK_M) * g_travel; }
MO* target_of(MO* ik) { return field_obj(ik, "Target"); }

Vec3 controller_fwd() { return rotate(bridge::view_quat(bridge::S_RROT), Vec3{0, 0, -1}); }   // OpenXR: -Z
float along_gun() {
    const Vec3 d = bridge::hand_pos(bridge::LEFT) - bridge::hand_pos(bridge::RIGHT);
    return d.x * g_axis.x + d.y * g_axis.y + d.z * g_axis.z;
}
// the left controller on the gun line: over the gun hand or ahead of it along the barrel, close to the line
bool near_joint(float& d) {   // the left controller (carried into the world) near the slide / pump joint itself
    Vec3 jp, lp;
    if (g_joint == nullptr || !get_v3(JOINT, g_joint, "get_Position", jp) || !bridge::room_to_world(bridge::hand_pos(bridge::LEFT), lp)) return false;
    d = dist(jp, lp);
    return d <= RACK_JOINT_GRAB_M;
}
bool on_gun_line(float& off) {
    const Vec3 fwd = controller_fwd(), v = bridge::hand_pos(bridge::LEFT) - bridge::hand_pos(bridge::RIGHT);
    const float ahead = v.x * fwd.x + v.y * fwd.y + v.z * fwd.z;
    const Vec3 side = v - fwd * ahead;
    off = std::sqrt(side.x * side.x + side.y * side.y + side.z * side.z);
    if (ahead >= -RACK_GRAB_BEHIND_M && ahead <= RACK_GRAB_AHEAD_MAX_M && off <= RACK_GRAB_M) return true;
    return dist(bridge::hand_pos(bridge::LEFT), bridge::hand_pos(bridge::RIGHT)) <= RACK_GRAB_ANY_M;   // the line may be off (2026-10-18)
}

void complete() {
    const bool was = g_needed;
    g_needed = g_parked = false;
    g_hold_closed = true;
    reload::on_racked();
    bridge::rumble(bridge::LEFT, RACK_BUZZ_AMP, RACK_BUZZ_SEC, RELOAD_BUZZ_HZ);
    LOGI("%s rack: %s %s cycle complete (%s), %d loaded", TAG, g_id.c_str(), part(), was ? "was needed: it fires again" : "cosmetic", player::loaded());
}

void hand_off(const char* why) {
    if (!g_hand_on) return;
    g_hand_on = g_armed = g_capture = g_rel_ok = false;
    if (bolt()) {   // a bolt let go mid-cycle stays where it is (turned / open) until the hand takes it again
        if (g_bstate != 0 || g_turn > 0.0f) LOGI("%s rack: hand off the bolt (%s): it stays at step %d", TAG, why, g_bstate);
        else g_turn = 0.0f;
        return;
    }
    if (g_pulled) { g_pulled = false; g_travel = 0.0f; complete(); }
    LOGI("%s rack: hand off the %s (%s), furthest pull %.3f m", TAG, part(), why, g_max_pull);
}

void write_joint() {
    if (g_joint == nullptr || !g_have_rest || !(g_hand_on || g_travel > 0.0f || g_turn > 0.0f || g_hold_closed)) return;
    Vec3 p{g_rest.x, g_rest.y, z_now()};
    set_any(JOINT, g_joint, "set_LocalPosition", &p);
    if (bolt()) {   // the bolt turns about the barrel (local Z) as it is lifted
        const float h = BOLT_TURN_DEG * g_turn * 3.14159265f / 360.0f;
        Quat q = qnorm(qmul(g_rest_rot, Quat{0, 0, std::sin(h), std::cos(h)}));
        set_any(JOINT, g_joint, "set_LocalRotation", &q);
    }
}

void click() {   // Andyalpa's chamber-open click (RE7 VR Reloaded), played on the PC's sound
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto f = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "sfx" / "bolt_click.wav";
    PlaySoundW(f.c_str(), nullptr, SND_FILENAME | SND_ASYNC | SND_NODEFAULT);
}

float hand_dy() { return bridge::hand_pos(bridge::LEFT).y - bridge::hand_pos(bridge::RIGHT).y; }
float clamp01(float v) { return std::fmax(0.0f, std::fmin(1.0f, v)); }

// one frame of the bolt cycle while the hand is on it (no LT: the hand on the bolt is enough)
void bolt_step() {
    const float turn_now = clamp01((hand_dy() - g_dy0) / BOLT_LIFT_M);
    const float want = clamp01((g_base - along_gun()) / RACK_PULL_M);
    switch (g_bstate) {
    case 0:
        g_turn = turn_now;
        if (g_turn >= 0.95f) { g_bstate = 1; g_turn = 1.0f; LOGI("%s rack: bolt turned up", TAG); }
        break;
    case 1:
        g_travel += (want - g_travel) * RACK_FOLLOW;
        if (g_travel >= 0.97f) {
            g_bstate = 2;
            g_pulled = true;
            click();
            bridge::rumble(bridge::LEFT, RACK_BUZZ_AMP, RACK_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s rack: bolt back (click): push it forward", TAG);
        }
        break;
    case 2:
        g_travel += (want - g_travel) * RACK_FOLLOW;
        if (g_travel <= BOLT_HOME) {
            g_bstate = 3;
            g_travel = 0.0f;
            g_dy0 = hand_dy() - BOLT_LIFT_M;   // from here, lowering the hand turns it down
            LOGI("%s rack: bolt home: turn it down to lock", TAG);
        }
        break;
    case 3:
        g_turn = turn_now;
        if (g_turn <= BOLT_DONE) {
            g_bstate = 0;
            g_turn = 0.0f;
            g_pulled = false;
            g_hand_on = g_armed = g_capture = g_rel_ok = false;
            complete();
            LOGI("%s rack: bolt locked", TAG);
        }
        break;
    }
}
} // namespace

bool needed() { return RELOAD_ON && rackable() && g_needed; }
bool active() { return g_hand_on; }
bool on_pump() { return g_hand_on && pump(); }
float travel() { return g_travel; }

void need(const char* why) {
    if (!rackable()) return;
    if (!g_needed) LOGI("%s rack: %s %s NEEDED (%s): the trigger waits until then", TAG, g_id.c_str(), pump() ? "pump" : "rack", why);
    g_needed = g_parked = true;
}

void frame() {
    if (!RELOAD_ON) return;
    const std::string id = weapons::canonical(player::now().weapon_id);
    if (id != g_id) {
        if (g_needed) LOGI("%s rack: %s put away with a rack pending (its rounds went in)", TAG, g_id.c_str());
        g_id = id;
        const auto* w = weapons::find(id);
        g_w = (w != nullptr && (w->rack || w->pump)) ? w : nullptr;
        g_needed = g_parked = g_hand_on = g_armed = g_pulled = g_spent = g_hold_closed = g_have_rest = g_capture = g_rel_ok = false;
        g_auto = 0;
        g_travel = 0.0f;
        g_bstate = 0;
        g_turn = 0.0f;
        g_last_loaded = -1;
        g_log_near = 0;
    }
    const auto& s = player::now();
    g_joint = nullptr;   // Village names its gun joints (headset log 2026-10-18: LEMI and F2 have "Slide")
    if (g_w != nullptr && s.weapon_tf != nullptr)
        for (const wchar_t* n : pump() ? std::initializer_list<const wchar_t*>{L"Reload_Slider", L"Pump", L"Forend"}   // M1897: Reload_Slider
                                       : std::initializer_list<const wchar_t*>{L"Slide", L"Bolt"})
            if ((g_joint = joint_by_name(s.weapon_tf, n)) != nullptr) break;
    if (g_joint != nullptr && !g_have_rest && get_v3(JOINT, g_joint, "get_LocalPosition", g_rest)) {
        g_have_rest = true;
        if (!get_q(JOINT, g_joint, "get_LocalRotation", g_rest_rot)) g_rest_rot = Quat{0, 0, 0, 1};
        LOGI("%s rack: %s %s joint rests at local %.3f %.3f %.3f", TAG, g_id.c_str(), part(), g_rest.x, g_rest.y, g_rest.z);
    }
    if (g_w == nullptr || s.gun == nullptr || !bridge::live()) { hand_off("no gun / no headset"); return; }

    const int loaded = player::loaded();
    const bool shot = g_last_loaded > 0 && loaded >= 0 && loaded < g_last_loaded && !reload::mag_out();
    if (g_hold_closed && shot) g_hold_closed = false;   // a shot
    // Tefa 2026-10-19: "pump handle pumping doesn't work, game still does that automatically": a pump gun now needs the
    // pump after every shot; its remaining shells wait in reload.cpp until then (the game's own pump motion still plays)
    if ((pump() || bolt()) && shot && loaded > 0 && !g_needed) need(pump() ? "pumped after the shot" : "the bolt after the shot");   // the trigger waits (reload.cpp)
    g_last_loaded = loaded;
    if (!pump() && !g_parked && !reload::mag_out() && loaded == 0) { g_parked = true; LOGI("%s rack: %s empty: it can be racked", TAG, g_id.c_str()); }

    const bool play = bridge::flag(bridge::S_CAN_USE_HANDS) && !bridge::flag(bridge::S_CUTSCENE);
    const bool lg = bridge::held(bridge::S_LGRIP), lt = bridge::held(bridge::S_LTRIG), lock = pose_lock();
    const bool may_rack = pump() || g_parked || g_needed || lock || (bolt() && (g_bstate != 0 || g_turn > 0.0f));   // a bolt mid-cycle can always be taken
    if (!lt) g_spent = false;

    if (!g_hand_on && play && may_rack && !g_spent && !reload::session_active() && !reload::in_pouch()) {
        // Tefa 2026-10-18: "suppress weapon docking on the handle when the slide needs racking": with a rack due, the left
        // grip held near the gun always takes the slide (our IK target wins over the VR layer's grip dock); with none due
        // the hand is never put on the slide (may_rack above), so the grip dock is left alone
        const bool want = pump() ? (lg && bridge::pressed(bridge::S_LTRIG)) : lg;
        if (want) {
            float off = 99.0f;
            const bool is_near = g_joint != nullptr ? near_joint(off) : on_gun_line(off);
            if (g_log_near < 30 && (pump() || bridge::pressed(bridge::S_LGRIP) || is_near)) {
                ++g_log_near;
                const Vec3 f = controller_fwd(), v = bridge::hand_pos(bridge::LEFT) - bridge::hand_pos(bridge::RIGHT);
                LOGI("%s rack: left hand %.3f m off the gun line (need %.2f): %s; gun line %.2f %.2f %.2f, left - right %.2f %.2f %.2f", TAG, off,
                     RACK_GRAB_M, is_near ? "HAND ON" : "too far", f.x, f.y, f.z, v.x, v.y, v.z);
            }
            if (is_near && bolt()) {
                g_hand_on = g_capture = g_armed = true;
                g_rel_ok = false;
                const Vec3 v = bridge::hand_pos(bridge::LEFT) - bridge::hand_pos(bridge::RIGHT);
                const float len = std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
                g_axis = len > 0.10f ? v * (1.0f / len) : controller_fwd();
                g_base = along_gun() + g_travel * RACK_PULL_M;            // the travel carries on from where the bolt is
                g_dy0 = hand_dy() - g_turn * BOLT_LIFT_M;                 // and so does the turn
                bridge::rumble(bridge::LEFT, RACK_BUZZ_AMP * 0.5f, RACK_BUZZ_SEC, RELOAD_BUZZ_HZ);
            } else if (is_near) {
                g_hand_on = g_capture = true;
                g_pulled = g_armed = g_rel_ok = false;
                bridge::rumble(bridge::LEFT, RACK_BUZZ_AMP * 0.5f, RACK_BUZZ_SEC, RELOAD_BUZZ_HZ);
            }
        }
    }
    if (g_hand_on && bolt()) {
        if (!play) hand_off("cutscene / hands not free");
        else if (!lg && !lock) hand_off("LG let go");
        else bolt_step();
        return;
    }
    if (g_hand_on) {
        if (!g_armed && lt && (pump() || bridge::pressed(bridge::S_LTRIG))) {
            g_armed = true;
            g_axis = controller_fwd();
            // long guns: the left hand sits ahead on the barrel, so the barrel runs from the right hand to it
            const Vec3 v = bridge::hand_pos(bridge::LEFT) - bridge::hand_pos(bridge::RIGHT);
            const float len = std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
            if (g_w->shape == weapons::Shape::LONG && len > 0.10f) g_axis = v * (1.0f / len);
            g_base = along_gun();
            g_max_pull = 0.0f;
        }
        if (!play) hand_off("cutscene / hands not free");
        else if (lock) { /* "hold this pose": the hand stays on, whatever the buttons do */ }
        else if (pump() && g_pulled && !lt && g_auto != 2) { g_auto = 2; g_auto_t0 = now_s(); }
        else if (pump() && !g_pulled && !lt) hand_off("LT let go before the handle was back");
        else if (!lg) hand_off(g_pulled ? "LG let go: it goes forward" : "LG let go");
        else if (!pump() && !g_pulled && g_armed && !lt) g_armed = false;
    }

    if (g_hand_on && g_armed && g_auto == 2) {
        const float t = (now_s() - g_auto_t0) / PUMP_RETURN_SEC;
        g_travel = std::fmax(0.0f, 1.0f - t);
        if (t >= 1.0f) { g_auto = 0; g_spent = lt; hand_off("pump cycle done"); }
    } else if (g_hand_on && g_armed) {
        const float pulled = g_base - along_gun();
        g_max_pull = std::fmax(g_max_pull, pulled);
        const float want = !g_pulled ? std::fmax(0.0f, std::fmin(1.0f, pulled / RACK_PULL_M))
                                     : std::fmax(0.0f, std::fmin(1.0f, 1.0f - (g_max_pull - pulled) / RACK_RETURN_M));
        if (pump() || !g_pulled) g_travel += (want - g_travel) * RACK_FOLLOW;
        else g_travel = 1.0f;
        if (!g_pulled && g_travel >= 0.97f) {
            g_pulled = true;
            bridge::rumble(bridge::LEFT, RACK_BUZZ_AMP, RACK_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s rack: pulled back (%.3f m)", TAG, pulled);
        }
        if (pump() && g_pulled && lt && g_travel <= 0.10f) { g_spent = true; hand_off("pumped back by hand"); }
    } else if (!g_pulled && g_travel > 0.0f) {
        g_travel = std::fmax(0.0f, g_travel - RACK_SPRING_STEP);
    }
}

void begin_render_point() { write_joint(); }

void late_point() {
    g_slide_ok = false;
    const auto& s = player::now();
    Vec3 rp, jp, lp, gp;
    Quat rq, gq;
    if (g_joint != nullptr && player::get_pose(target_of(s.ik_right), rp, rq) && get_v3(JOINT, g_joint, "get_Position", jp) &&
        get_v3(JOINT, g_joint, "get_LocalPosition", lp) && get_v3(XFORM, s.weapon_tf, "get_Position", gp) && get_q(XFORM, s.weapon_tf, "get_Rotation", gq)) {
        const Quat inv = qinv(rq);
        g_slide_pos = rotate(inv, jp - rp);
        g_slide_gun = qnorm(qmul(inv, qnorm(gq)));
        g_z_anim = lp.z;
        g_slide_ok = true;
    }
    write_joint();
}
void render_point() { write_joint(); }

void on_ik(MO* ik) {
    const auto& s = player::now();
    if (!g_hand_on || ik != s.ik_left) return;
    Vec3 rp, lp;
    Quat rq, lq;
    if (!player::get_pose(target_of(s.ik_right), rp, rq)) return;
    if (g_capture) {   // where the VR layer put the hand this frame, relative to the gun hand, becomes its place on the gun
        if (!player::get_pose(target_of(ik), lp, lq)) return;
        const Quat inv = qinv(rq);
        g_rel_pos = rotate(inv, lp - rp);
        g_rel_rot = qnorm(qmul(inv, lq));
        g_capture = false;
        g_rel_ok = true;
    }
    if (!g_rel_ok) return;
    const Quat rot = qnorm(qmul(rq, g_rel_rot));
    if (g_slide_ok) {   // on the slide joint, riding its travel, nudged by the menu sliders (gun axes: x right, y up, z forward)
        const Quat gun = qnorm(qmul(rq, g_slide_gun));
        const Vec3 nudge{bridge::view(bridge::S_SLIDE_HAND_X) * 0.01f, bridge::view(bridge::S_SLIDE_HAND_Y) * 0.01f, bridge::view(bridge::S_SLIDE_HAND_Z) * 0.01f};
        const Vec3 pos = rp + rotate(rq, g_slide_pos) + rotate(gun, Vec3{0, 0, z_now() - g_z_anim} + (bridge::has(nudge.x) ? nudge : Vec3{0, 0, 0}));
        player::set_pose(target_of(ik), pos, rot);
        return;
    }
    Vec3 back{0, 0, 0};   // no slide joint: where the hand took hold, slid back with the pull
    if (g_travel > 0.0f && bridge::room_dir_to_world(g_axis * (-RACK_PULL_M * g_travel), back) == false) back = Vec3{0, 0, 0};
    player::set_pose(target_of(ik), rp + rotate(rq, g_rel_pos) + back, rot);
}

} // namespace vn::rack
