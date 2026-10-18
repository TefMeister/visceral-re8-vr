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

bool g_capture = false;       // take the hand's place on the gun at the next left-arm solve
bool g_rel_ok = false;
Vec3 g_rel_pos{};
Quat g_rel_rot{0, 0, 0, 1};

bool pose_lock() { return bridge::flag(bridge::S_POSE_LOCK); }
bool pump() { return g_w != nullptr && g_w->pump; }
bool rackable() { return g_w != nullptr && (g_w->rack || g_w->pump); }
const char* part() { return pump() ? "pump" : "slide"; }
float z_now() { return g_rest.z + (pump() ? PUMP_BACK_M : SLIDE_BACK_M) * g_travel; }
MO* target_of(MO* ik) { return field_obj(ik, "Target"); }

Vec3 controller_fwd() { return rotate(bridge::view_quat(bridge::S_RROT), Vec3{0, 0, -1}); }   // OpenXR: -Z
float along_gun() {
    const Vec3 d = bridge::hand_pos(bridge::LEFT) - bridge::hand_pos(bridge::RIGHT);
    return d.x * g_axis.x + d.y * g_axis.y + d.z * g_axis.z;
}
// the left controller on the gun line: over the gun hand or ahead of it along the barrel, close to the line
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
    if (g_pulled) { g_pulled = false; g_travel = 0.0f; complete(); }
    LOGI("%s rack: hand off the %s (%s), furthest pull %.3f m", TAG, part(), why, g_max_pull);
}

void write_joint() {
    if (g_joint == nullptr || !g_have_rest || !(g_hand_on || g_travel > 0.0f || g_hold_closed)) return;
    Vec3 p{g_rest.x, g_rest.y, z_now()};
    set_any(JOINT, g_joint, "set_LocalPosition", &p);
}
} // namespace

bool needed() { return RELOAD_ON && rackable() && g_needed; }
bool active() { return g_hand_on; }
bool on_pump() { return g_hand_on && pump(); }
float travel() { return g_travel; }

void need(const char* why) {
    if (!rackable()) return;
    if (!g_needed) LOGI("%s rack: %s %s NEEDED (%s): the gun reads empty until then", TAG, g_id.c_str(), pump() ? "pump" : "rack", why);
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
        g_last_loaded = -1;
        g_log_near = 0;
    }
    const auto& s = player::now();
    g_joint = nullptr;   // Village names its gun joints (headset log 2026-10-18: LEMI and F2 have "Slide")
    if (g_w != nullptr && s.weapon_tf != nullptr)
        for (const wchar_t* n : {L"Slide", L"Pump", L"Forend", L"Bolt"}) if ((g_joint = joint_by_name(s.weapon_tf, n)) != nullptr) break;
    if (g_joint != nullptr && !g_have_rest && get_v3(JOINT, g_joint, "get_LocalPosition", g_rest)) {
        g_have_rest = true;
        LOGI("%s rack: %s %s joint rests at local %.3f %.3f %.3f", TAG, g_id.c_str(), part(), g_rest.x, g_rest.y, g_rest.z);
    }
    if (g_w == nullptr || s.gun == nullptr || !bridge::live()) { hand_off("no gun / no headset"); return; }

    const int loaded = player::loaded();
    if (g_hold_closed && g_last_loaded > 0 && loaded >= 0 && loaded < g_last_loaded) g_hold_closed = false;   // a shot
    g_last_loaded = loaded;
    if (!pump() && !g_parked && !reload::mag_out() && loaded == 0) { g_parked = true; LOGI("%s rack: %s empty: it can be racked", TAG, g_id.c_str()); }

    const bool play = bridge::flag(bridge::S_CAN_USE_HANDS) && !bridge::flag(bridge::S_CUTSCENE);
    const bool lg = bridge::held(bridge::S_LGRIP), lt = bridge::held(bridge::S_LTRIG), lock = pose_lock();
    const bool may_rack = pump() || g_parked || g_needed || lock;
    if (!lt) g_spent = false;

    if (!g_hand_on && play && may_rack && !g_spent && !reload::session_active() && !reload::in_pouch()) {
        const bool want = pump() ? (lg && bridge::pressed(bridge::S_LTRIG)) : bridge::pressed(bridge::S_LGRIP) || (lg && bridge::pressed(bridge::S_LTRIG));
        if (want) {
            float off = 99.0f;
            const bool near = on_gun_line(off);
            if (g_log_near < 30) {
                ++g_log_near;
                const Vec3 f = controller_fwd(), v = bridge::hand_pos(bridge::LEFT) - bridge::hand_pos(bridge::RIGHT);
                LOGI("%s rack: left hand %.3f m off the gun line (need %.2f): %s; gun line %.2f %.2f %.2f, left - right %.2f %.2f %.2f", TAG, off,
                     RACK_GRAB_M, near ? "HAND ON" : "too far", f.x, f.y, f.z, v.x, v.y, v.z);
            }
            if (near) {
                g_hand_on = g_capture = true;
                g_pulled = g_armed = g_rel_ok = false;
                bridge::rumble(bridge::LEFT, RACK_BUZZ_AMP * 0.5f, RACK_BUZZ_SEC, RELOAD_BUZZ_HZ);
            }
        }
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

void late_point() { write_joint(); }
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
    Vec3 back{0, 0, 0};
    if (g_travel > 0.0f && bridge::room_dir_to_world(g_axis * (-RACK_PULL_M * g_travel), back) == false) back = Vec3{0, 0, 0};
    player::set_pose(target_of(ik), rp + rotate(rq, g_rel_pos) + back, qnorm(qmul(rq, g_rel_rot)));
}

} // namespace vn::rack
