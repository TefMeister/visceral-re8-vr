// rack.cpp -- see rack.h. Gesture and timings from Visceral RE2's rack.cpp via RE7; the grab test is in the room, from
// the controllers (RE2 b162's pump test, used for every gun here), and the hand's place on the gun is captured from the
// left IK target at the moment it takes hold.
#include "rack.h"
#include "bridge.h"
#include "ghosthand.h"
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
bool g_slide_frozen = false;  // the spot is kept from the first measure after taking hold (the game animates the pump joint)
bool g_rel_ok = false;
Vec3 g_rel_pos{};
Quat g_rel_rot{0, 0, 0, 1};
Quat g_rest_rot{0, 0, 0, 1};

// the bolt cycle: 0 locked, 1 turned up, 2 pulled back (clicked), 3 pushed home (still up); turned down from 3 = done
int g_bstate = 0;
float g_turn = 0.0f;          // 0 = down / locked, 1 = up

// the wrist-to-palm offset in the left IK target's own frame (L_Hand -> L_Palm), measured after each frame's solves
bool g_palm_ok = false;
Vec3 g_palm_t{};
int g_palm_logs = 0, g_palm_misses = 0;
float g_palm_closest = 99.0f;

bool pose_lock() { return bridge::flag(bridge::S_POSE_LOCK); }
bool pump() { return g_w != nullptr && g_w->pump; }
bool bolt() { return g_w != nullptr && g_w->bolt; }
bool rackable() { return g_w != nullptr && (g_w->rack || g_w->pump); }
const char* part() { return pump() ? "pump" : bolt() ? "bolt" : "slide"; }
float z_now() { return g_rest.z + (pump() ? PUMP_BACK_M : SLIDE_BACK_M) * g_travel; }
MO* target_of(MO* ik) { return field_obj(ik, "Target"); }

Vec3 controller_fwd() { return rotate(bridge::view_quat(bridge::S_RROT), Vec3{0, 0, -1}); }   // OpenXR: -Z
Vec3 unit_or(Vec3 v, Vec3 fallback) {
    const float len = std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    return len > 1e-4f ? v * (1.0f / len) : fallback;
}
// the barrel in the room, carried through the camera. 2026-10-24 (Tefa: "i think the bolt racking works backwards"): the
// gun object's +Z was only assumed to point at the muzzle, so the barrel is now the line from the gun to its own
// "vfx_muzzle" joint when the gun has one; the old +Z guess is kept as the fallback and the two are compared in the log once.
// 2026-10-19: the bolt's pull was read along the line between the hands, which is short and crooked when the left hand
// sits over the receiver, and the bolt would not follow the controller.
Vec3 barrel_room() {
    const auto& s = player::now();
    Quat gq;
    Vec3 gp{}, mp{}, f{};
    const bool have_gun = get_q(XFORM, s.weapon_tf, "get_Rotation", gq) && get_v3(XFORM, s.weapon_tf, "get_Position", gp);
    const Vec3 plus_z = have_gun ? rotate(qnorm(gq), Vec3{0, 0, 1}) : Vec3{0, 0, 0};
    MO* muzzle = s.weapon_tf != nullptr ? joint_by_name(s.weapon_tf, L"vfx_muzzle") : nullptr;
    if (have_gun && muzzle != nullptr && get_v3(JOINT, muzzle, "get_Position", mp) && dist(mp, gp) > BARREL_MUZZLE_MIN_M) {
        const Vec3 to_muzzle = unit_or(mp - gp, plus_z);
        static std::string told;
        if (told != g_id) {
            told = g_id;
            const float d = to_muzzle.x * plus_z.x + to_muzzle.y * plus_z.y + to_muzzle.z * plus_z.z;
            LOGI("%s rack: %s barrel from the muzzle joint; the old +Z guess agreed by %.2f (1 = same, -1 = backwards)", TAG, g_id.c_str(), d);
        }
        if (bridge::world_dir_to_room(to_muzzle, f)) return unit_or(f, controller_fwd());
    }
    if (have_gun && bridge::world_dir_to_room(plus_z, f)) {
        const float len = std::sqrt(f.x * f.x + f.y * f.y + f.z * f.z);
        if (len > 0.5f) return f * (1.0f / len);
    }
    const Vec3 v = bridge::hand_pos(bridge::LEFT) - bridge::hand_pos(bridge::RIGHT);
    const float len = std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    return len > 0.10f ? v * (1.0f / len) : controller_fwd();
}
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
    if (!pump() && !bolt()) bridge::sfx(bridge::SFX_SLIDE_FORWARD);   // the slide slams home (the bolt and pump say their own)
    ghosthand::event(part(), "done");
    g_needed = g_parked = false;
    g_hold_closed = true;
    reload::on_racked();
    bridge::rumble(bridge::LEFT, RACK_BUZZ_AMP, RACK_BUZZ_SEC, RELOAD_BUZZ_HZ);
    LOGI("%s rack: %s %s cycle complete (%s), %d loaded", TAG, g_id.c_str(), part(), was ? "was needed: it fires again" : "cosmetic", player::loaded());
}

void hand_off(const char* why) {
    if (!g_hand_on) return;
    if (g_armed && !g_pulled && !(bolt() && g_bstate != 0)) {   // armed and let go before anything finished
        ghosthand::value(std::string(part()).append("_max_pull_m").c_str(), g_max_pull);
        ghosthand::event(part(), "cancel");
    }
    g_hand_on = g_armed = g_capture = g_rel_ok = g_slide_frozen = false;
    if (pump() && g_pulled && g_travel > 0.10f) {   // a pump let go before it is pushed back up stays there
        LOGI("%s rack: hand off the pump (%s): it stays back, push it up to finish", TAG, why);
        return;
    }
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

float clamp01(float v) { return std::fmax(0.0f, std::fmin(1.0f, v)); }
float g_bolt_t = -1.0f;       // the last frame's clock, for the bolt's own lift and drop

// 2026-10-24, the bolt redone (Tefa: "LG puts the left hand on the bolt, holding LT then lifts the bolt up with hand so
// player only has to do the backward and forward motion, click must play both when bolt is in the back and when pushed
// forward again ... then when the bolt is all the way back in front, it automatically goes back down"). So: with LT held
// the bolt turns up by itself, then follows the hand back (click) and forward (click), and once home it turns down by
// itself, LT or not. LT let go mid-way: it stays where it is until LT is held again.
void bolt_step(bool lt) {
    const float now = now_s();
    const float dt = g_bolt_t < 0.0f ? 0.0f : std::fmin(0.1f, now - g_bolt_t);
    g_bolt_t = now;
    const float want = clamp01((g_base - along_gun()) / RACK_PULL_M);
    switch (g_bstate) {
    case 0:
        if (!lt || g_spent) break;   // a finished cycle wants LT let go once before the next one
        g_turn = clamp01(g_turn + dt / BOLT_LIFT_SEC);
        if (g_turn >= 1.0f) {
            g_bstate = 1;
            g_base = along_gun();   // the pull is measured from where the hand is once the bolt is up
            bridge::sfx(bridge::SFX_BOLT_UP);
            LOGI("%s rack: bolt turned up by itself: pull it back", TAG);
        }
        break;
    case 1:
        if (!lt) break;
        g_travel += (want - g_travel) * RACK_FOLLOW;
        if (g_travel >= 0.97f) {
            g_bstate = 2;
            g_pulled = true;
            bridge::sfx(bridge::SFX_BOLT_BACK);
            bridge::rumble(bridge::LEFT, RACK_BUZZ_AMP, RACK_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s rack: bolt back (click): push it forward", TAG);
        }
        break;
    case 2:
        if (!lt) break;
        g_travel += (want - g_travel) * RACK_FOLLOW;
        if (g_travel <= BOLT_HOME) {
            g_bstate = 3;
            g_travel = 0.0f;
            bridge::sfx(bridge::SFX_BOLT_FORWARD);
            bridge::rumble(bridge::LEFT, RACK_BUZZ_AMP, RACK_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s rack: bolt home (click): it turns down by itself", TAG);
        }
        break;
    case 3:
        g_turn = clamp01(g_turn - dt / BOLT_LIFT_SEC);
        if (g_turn <= 0.0f) {
            g_bstate = 0;
            g_pulled = false;
            g_armed = false;
            g_spent = true;
            bridge::sfx(bridge::SFX_BOLT_DOWN);
            complete();
            LOGI("%s rack: bolt locked", TAG);
        }
        break;
    }
}
} // namespace

bool needed() { return RELOAD_ON && rackable() && g_needed; }
void* slide_joint() { return g_joint; }
const char* part_name() { return part(); }
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
        // pump and bolt: LG held + one LT press near it starts the cycle (Tefa 2026-10-19: "LT needs to be pressed once not even
        // held throughout, but it is needed for a cleaner sequence"); the slide: LG alone
        // Tefa 2026-10-19, for every weapon: "the left grip must already grip it and hold on, but not move ... until LT is pressed"
        const bool want = lg;
        if (want) {
            float off = 99.0f;
            const bool is_near = g_joint != nullptr ? near_joint(off) : on_gun_line(off);
            if (g_log_near < 30 && (bridge::pressed(bridge::S_LGRIP) || is_near)) {
                ++g_log_near;
                const Vec3 f = controller_fwd(), v = bridge::hand_pos(bridge::LEFT) - bridge::hand_pos(bridge::RIGHT);
                LOGI("%s rack: left hand %.3f m off the gun line (need %.2f): %s; gun line %.2f %.2f %.2f, left - right %.2f %.2f %.2f", TAG, off,
                     RACK_GRAB_M, is_near ? "HAND ON" : "too far", f.x, f.y, f.z, v.x, v.y, v.z);
            }
            if (is_near && bolt()) {   // Tefa 2026-10-19: "the left grip must already grip it and hold on, but not move the bolt until LT is pressed"
                g_hand_on = g_capture = true;
                g_armed = g_rel_ok = false;
                bridge::rumble(bridge::LEFT, RACK_BUZZ_AMP * 0.5f, RACK_BUZZ_SEC, RELOAD_BUZZ_HZ);
            } else if (is_near) {
                g_hand_on = g_capture = true;
                g_pulled = g_armed = g_rel_ok = false;
                bridge::rumble(bridge::LEFT, RACK_BUZZ_AMP * 0.5f, RACK_BUZZ_SEC, RELOAD_BUZZ_HZ);
            }
        }
    }
    if (bolt() && !g_hand_on && g_bstate == 3) { bolt_step(false); return; }   // home: it turns down by itself, hand or not
    if (g_hand_on && bolt()) {
        if (!play) { hand_off("cutscene / hands not free"); return; }
        if (!lg && !lock) { hand_off("LG let go"); return; }
        // 2026-10-24 (Tefa: "LT needs to be held the whole time to work it"): the bolt works only while LT is held
        if (lt && !g_armed) {
            g_armed = true;
            g_axis = barrel_room();
            g_base = along_gun() + g_travel * RACK_PULL_M;   // the travel carries on from where the bolt is
            LOGI("%s rack: bolt held with LT", TAG);
            ghosthand::event("bolt", "start");
        } else if (!lt && g_armed) {
            g_armed = false;
            if (g_bstate != 3) LOGI("%s rack: LT let go: the bolt stays at step %d", TAG, g_bstate);
        }
        bolt_step(lt && g_armed);
        return;
    }
    if (g_hand_on) {
        // 2026-10-24 (Tefa: "LG is used to put hand on the slider/handle/bolt and LT needs to be held the whole time to work
        // it"): LT held = the slide / pump follows the hand; LT let go = the slide goes home, the pump stays where it is
        if (lt && !g_armed && !g_spent) {
            g_armed = true;
            ghosthand::event(part(), "start");
            g_axis = barrel_room();
            // the pump: the left hand sits well ahead on the barrel, so the line from the right hand to it works (worn 2026-10-19)
            const Vec3 v = bridge::hand_pos(bridge::LEFT) - bridge::hand_pos(bridge::RIGHT);
            const float len = std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
            if (pump() && len > 0.10f) g_axis = v * (1.0f / len);
            g_base = along_gun() + (g_pulled ? 0.0f : g_travel * RACK_PULL_M);   // a part-way pull carries on from there
            g_max_pull = 0.0f;
            if (pump() && g_pulled) g_max_pull = (1.0f - g_travel) * RACK_RETURN_M;   // a pump left back carries on from there
        } else if (!lt && g_armed && !lock) {
            g_armed = false;
            if (!pump() && g_pulled) {   // the slide let go of at the back: it slams home
                g_pulled = false;
                g_travel = 0.0f;
                complete();
                g_spent = true;
                LOGI("%s rack: LT let go at the back: the slide went home", TAG);
            } else {
                LOGI("%s rack: LT let go: the %s %s", TAG, part(), pump() ? "stays where it is" : "springs back");
            }
        }
        if (!play) hand_off("cutscene / hands not free");
        else if (lock) { /* "hold this pose": the hand stays on, whatever the buttons do */ }
        else if (!lg) hand_off(g_pulled && !pump() ? "LG let go: it goes forward" : "LG let go");
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
            bridge::sfx(pump() ? bridge::SFX_PUMP_BACK : bridge::SFX_SLIDE_BACK);
            bridge::rumble(bridge::LEFT, RACK_BUZZ_AMP, RACK_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s rack: pulled back (%.3f m)", TAG, pulled);
        }
        if (pump() && g_pulled && g_travel <= 0.10f) { bridge::sfx(bridge::SFX_PUMP_FORWARD); hand_off("pumped back up by hand"); }
    } else if (!g_pulled && g_travel > 0.0f && !(pump() && g_hand_on)) {   // a pump only springs back once the hand is off it
        g_travel = std::fmax(0.0f, g_travel - RACK_SPRING_STEP);
    }
}

void begin_render_point() { write_joint(); }

void late_point() {
    if (g_hand_on && g_slide_frozen) { write_joint(); return; }   // Tefa 2026-10-19: the hand wandered on the shotgun's fore-end
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
        if (g_hand_on) { g_slide_frozen = true; g_z_anim = z_now(); }   // the joint's own place now = travel offset 0 from here
    }
    write_joint();
}
// 2026-10-24 (Tefa: "gun goes through the left wrist not the palm for LEMI and the shotgun"): the IK target is the wrist,
// so the hand is moved back by the wrist-to-palm offset. Measured here, after the frame's solves, only when the drawn wrist
// reached its target (else the arm was short and the numbers would lie)
void measure_palm() {
    const auto& s = player::now();
    static MO* tf_seen = nullptr;
    static MO *hand = nullptr, *palm = nullptr;
    if (s.tf == nullptr || s.ik_left == nullptr) return;
    if (s.tf != tf_seen) {
        tf_seen = s.tf;
        hand = joint_by_name(s.tf, L"L_Hand");
        palm = joint_by_name(s.tf, L"L_Palm");
        LOGI("%s rack: palm joints %s / %s", TAG, hand ? "L_Hand found" : "L_Hand MISSING", palm ? "L_Palm found" : "L_Palm MISSING (the wrist stays on the slide)");
    }
    Vec3 hp, pp, tp;
    Quat tq;
    if (hand == nullptr || palm == nullptr || !get_v3(JOINT, hand, "get_Position", hp) || !get_v3(JOINT, palm, "get_Position", pp) ||
        !player::get_pose(target_of(s.ik_left), tp, tq))
        return;
    const float reach = dist(hp, tp);
    if (reach > PALM_MEASURE_REACH_M) {
        g_palm_closest = std::fmin(g_palm_closest, reach);
        if (!g_palm_ok && ++g_palm_misses == 600)
            LOGI("%s rack: the palm offset is not measured yet: the drawn wrist never came within %.3f m of its target (closest %.3f m)", TAG,
                 PALM_MEASURE_REACH_M, g_palm_closest);
        return;
    }
    const Vec3 v = rotate(qinv(qnorm(tq)), pp - hp);
    if (g_palm_logs < 5 && (!g_palm_ok || dist(v, g_palm_t) > 0.005f)) {
        ++g_palm_logs;
        LOGI("%s rack: wrist to palm %.3f m (in the hand target's frame %.3f %.3f %.3f), wrist %.3f m from its target", TAG,
             dist(pp, hp), v.x, v.y, v.z, reach);
    }
    g_palm_t = v;
    g_palm_ok = true;
}

void render_point() {
    write_joint();
    if (PALM_ON_SLIDE) measure_palm();
}

// 2026-10-24 (Tefa: on the slide the hand "sits there with its wrist ready to rack and hand fully visible on the right
// hand side"): the menu's three turn sliders turn the hand about the gun's own axes (x right, y up, z forward), in degrees
Quat slide_hand_turn(Quat gun) {
    const float d = 3.14159265f / 360.0f;
    const float ax = bridge::view(bridge::S_SLIDE_HAND_ROT), ay = bridge::view((bridge::Slot)(bridge::S_SLIDE_HAND_ROT + 1)),
                az = bridge::view((bridge::Slot)(bridge::S_SLIDE_HAND_ROT + 2));
    if (!bridge::has(ax) || (ax == 0.0f && ay == 0.0f && az == 0.0f)) return Quat{0, 0, 0, 1};
    const Quat local = qnorm(qmul(qmul(Quat{0, std::sin(ay * d), 0, std::cos(ay * d)}, Quat{std::sin(ax * d), 0, 0, std::cos(ax * d)}),
                                  Quat{0, 0, std::sin(az * d), std::cos(az * d)}));
    return qnorm(qmul(qmul(gun, local), qinv(gun)));
}

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
        const Quat hand_q = qnorm(qmul(slide_hand_turn(gun), rot));
        Vec3 offs = rotate(gun, bridge::has(nudge.x) ? nudge : Vec3{0, 0, 0});
        if (PALM_ON_SLIDE && g_palm_ok && !bolt()) offs = offs - rotate(hand_q, g_palm_t);   // the palm on the part, not the wrist
        const Vec3 pivot = rp + rotate(rq, g_slide_pos) + rotate(gun, Vec3{0, 0, z_now() - g_z_anim});
        Quat turn{0, 0, 0, 1};
        if (bolt() && g_turn > 0.0f) {   // Tefa 2026-10-24: "left hand must follow the bolt racking movement all 4 moves": up and down too
            const float h = BOLT_TURN_DEG * g_turn * 3.14159265f / 360.0f;
            const Quat jf = qnorm(qmul(gun, g_rest_rot));   // the bolt joint's frame at rest: it turns about its own Z (write_joint)
            turn = qnorm(qmul(qmul(jf, Quat{0, 0, std::sin(h), std::cos(h)}), qinv(jf)));
        }
        player::set_pose(target_of(ik), pivot + rotate(turn, offs), qnorm(qmul(turn, hand_q)));
        return;
    }
    Vec3 back{0, 0, 0};   // no slide joint: where the hand took hold, slid back with the pull
    if (g_travel > 0.0f && bridge::room_dir_to_world(g_axis * (-RACK_PULL_M * g_travel), back) == false) back = Vec3{0, 0, 0};
    player::set_pose(target_of(ik), rp + rotate(rq, g_rel_pos) + back, rot);
}

} // namespace vn::rack
