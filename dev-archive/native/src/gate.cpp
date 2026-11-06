// gate.cpp -- see gate.h. Built on rack_right.cpp's way of holding a gun in the left hand (proven on the F2's bolt).
#include "gate.h"
#include "breech.h"
#include "bridge.h"
#include "drumrounds.h"
#include "joints.h"
#include "json_mini.h"
#include "player.h"
#include "reload.h"
#include "settings.h"
#include "shellclip.h"
#include "weapons.h"

#include <windows.h>
#include <mmsystem.h>

#include <algorithm>
#include <filesystem>
#include <cmath>
#include <cstdio>
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

enum class Phase { OFF, HELD, RETURN, HANDOVER, STAY, HAMMER };
const char* phase_name(Phase p) {
    return p == Phase::HELD ? "held by the left hand" : p == Phase::RETURN ? "right hand back to the grip" : p == Phase::HANDOVER ? "handed back" : p == Phase::STAY ? "left hand stays on the drum" : p == Phase::HAMMER ? "left palm on the hammer" : "off";
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
// 2026-11-06 (Tefa: "after reloading has finished and right hand is aiming the gun again, left hand is loosely riding along, not
// firmly docked on the weapon as it was during reloading"): in STAY (and on the hammer) the left hand was placed from the gun's
// place read at UpdateBehavior, before this frame's right-arm solve moved it: one frame behind, so it trailed the gun. Now it is
// pinned to the right hand's IK target at the left solve, as rack.cpp holds the pump hand. The gun's place against that target
// is measured every frame from matching numbers (the target at last frame's right solve, the gun where that solve put it).
Pose g_rt_ik{};              // the right hand's target as its last solve had it
bool g_rt_ik_ok = false;
// 2026-11-06 (Tefa: "After the reload is done and right hand has control, left hand must stay docked still but the hand pose
// must change to just hold it so that fingers are not on the drum anymore, otherwise the drum rotation animation plays with
// fingers standing still on it"): in STAY the left hand glides from the drum to the place the game's own two-handed grip last
// held it (kept while that grip held it), or, never seen, a guessed support place below the drum (GATE_STAY_HOLD_OFF), and
// tells Hand Poser spot 0 (the gun's own hold) instead of the drum (6)
Pose g_grip_left_in_gun{};
bool g_have_left_hold = false;
Pose g_stay_from{}, g_stay_to{};
float g_stay_t0 = 0.0f;
// 2026-11-06 (Tefa: "when having left hand on the hammer and pressing RT once, the drum still rotates on it's own after that. with
// LG on the hammer, only LT should rotate the drum"): with the palm on the hammer the drum is held as it was at the dock and
// turns one chamber per LT cock, drawn over GATE_CYL_TURN_SEC, whatever the game's shot animation does
MO* g_ham_cyl = nullptr;
Quat g_ham_cyl_q0{0, 0, 0, 1};
int g_ham_turns = 0;
float g_ham_draw = 0.0f, g_ham_t = -1.0f;
// the right hand's lift over the hammer (gate.h, 2026-11-06)
enum class Lift { NONE, UP, HOLD, DOWN };
Lift g_lift = Lift::NONE;
float g_lift_t0 = 0.0f, g_lift_u = 0.0f;
Pose g_lift_gun_in_rt{};     // the gun against the right hand's (unlifted) target, at the lift's start
Pose g_lift_gun{};           // the gun as the controller holds it, this frame (written at the late points)
bool g_lift_gun_ok = false;
MO* g_lift_tf = nullptr;
Vec3 g_lift_local_p{};
Quat g_lift_local_q{0, 0, 0, 1};
bool g_lift_parented = false;
Vec3 g_lift_off = GATE_LIFT_OFF, g_lift_axis = GATE_LIFT_AXIS;
float g_lift_deg = GATE_LIFT_DEG;
Pose g_gun_in_rt{};          // the gun against that target (OFF / STAY / HAMMER: the gun on the right hand)
bool g_gun_in_rt_ok = false;
int g_pin_lines = 0;

Vec3 g_left_off = GATE_LEFT_OFF, g_right_off = GATE_RIGHT_OFF, g_cyl_axis = GATE_CYL_AXIS, g_hammer_off = GATE_HAMMER_OFF;
bool g_cocked = true;      // 2026-11-01: the palm on the hammer: a shot leaves it down until LT pushes it back
// 2026-11-01 23:5x (Tefa: "game still does the cocking with right hand and LT does nothing. LG must suppress the game from cocking
// the hammer with right thumb automatically"): while the palm is on the hammer the right thumb and the hammer are written by us
// after the animation: the thumb as it was at the take, the hammer cocked (as at the take) or down (after a shot, until LT)
const wchar_t* const THUMB[3] = {L"R_Thumb1", L"R_Thumb2", L"R_Thumb3"};
MO* g_thumb[3] = {};
Quat g_thumb_q[3] = {};
MO* g_hammer = nullptr;
Quat g_hammer_cocked{0, 0, 0, 1};
bool g_hammer_cap = false;
Vec3 g_hammer_axis = GATE_HAMMER_AXIS;
float g_hammer_deg = GATE_HAMMER_DOWN_DEG;
Vec3 g_flick_axis = GATE_FLICK_AXIS;
float g_flick_deg = GATE_FLICK_DEG;
int g_last_loaded = -1;
// 2026-11-06 (Tefa: "when LG is held with a live round ready to shoot, LT does nothing. when the drum needs rotating, LT must be the
// button that brings the hammer down, right now it happens automatically. also hand must be above the hammer and press down on
// it with LT, so it visibly goes down and up"): a shot no longer draws the hammer down; LT (only when it needs cocking) starts a
// PRESS: the palm goes down GATE_PRESS_M and back, the hammer down and back with it, over GATE_PRESS_SEC; at the bottom the
// hammer is cocked, the drum turns one chamber, and with RT held the shot goes off
float g_press_t0 = -1.0f;
bool g_press_cocked = false;   // this press has cocked (at its bottom)
// 2026-11-06 (Tefa: "muzzle flash after every shot"): the fan shots fell back to requestShootForProcess (no flash) because the
// game's own timer lock (ShootableTime 1.5 s) re-shut every frame; with the palm on the hammer ShootableTime is made short
// (GATE_FAN_SHOOTABLE_S) so the game's own shot, with its flash, goes off; the gun's own value is put back after
float g_st_orig = -1.0f;
MO* g_st_gun = nullptr;
float press_curve(float now) {   // 0 -> 1 -> 0 over the press
    if (g_press_t0 < 0.0f || GATE_PRESS_SEC <= 0.0f) return 0.0f;
    const float u = (now - g_press_t0) / GATE_PRESS_SEC;
    return u <= 0.0f || u >= 1.0f ? 0.0f : std::sin(3.14159265f * u);
}
void st_restore() {
    if (g_st_orig < 0.0f) return;
    if (g_st_gun != nullptr && g_st_gun == player::now().gun) if (float* st = field_ptr<float>(g_st_gun, "ShootableTime")) *st = g_st_orig;
    LOGI("%s gate: the gun's own ShootableTime %.3f put back", TAG, g_st_orig);
    g_st_orig = -1.0f; g_st_gun = nullptr;
}

void cock_sound() {   // the hammer being cocked (the same recording as the empty click: SND_MOT_RI3008_SE_MVT_PRE_SHOT)
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto f = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "sfx" / "dry_hammer.wav";
    PlaySoundW(f.c_str(), nullptr, SND_FILENAME | SND_ASYNC | SND_NODEFAULT);
}

// 2026-11-02 (Tefa: "left hand docks on the hammer at an angle my hand currently is, only the finger poses are saved but not how
// it sits on the hammer every time"): the left hand's turn on the gun at its first dock on the hammer (and on the drum hold) is
// kept per gun in reframework/data/visceral_re8/gate_turns.json and used at every dock after; Dock Poser tunes on top of it.
// Delete the file (or a line in it) to take a new one at the next dock.
std::filesystem::path turns_path() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    return std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "gate_turns.json";
}
bool kept_turn(const std::string& key, Quat& q) {
    json::Value v;
    if (!json::load_file(turns_path().wstring(), v)) return false;
    const auto* a = v.get(key);
    if (a == nullptr || a->kind != json::Value::ARR || a->arr.size() != 4) return false;
    q = qnorm({(float)a->arr[0].n, (float)a->arr[1].n, (float)a->arr[2].n, (float)a->arr[3].n});
    return true;
}
void keep_turn(const std::string& key, const Quat& q) {
    json::Value v;
    json::load_file(turns_path().wstring(), v);
    std::string out = "{";
    bool first = true;
    char buf[160];
    if (v.kind == json::Value::OBJ)
        for (const auto& [k, e] : v.obj) {
            if (k == key || e.kind != json::Value::ARR || e.arr.size() != 4) continue;
            std::snprintf(buf, sizeof(buf), "%s\n  \"%s\": [%.6f, %.6f, %.6f, %.6f]", first ? "" : ",", k.c_str(), e.arr[0].n, e.arr[1].n, e.arr[2].n, e.arr[3].n);
            out += buf; first = false;
        }
    std::snprintf(buf, sizeof(buf), "%s\n  \"%s\": [%.6f, %.6f, %.6f, %.6f]\n}\n", first ? "" : ",", key.c_str(), q.x, q.y, q.z, q.w);
    out += buf;
    if (FILE* f = _wfopen(turns_path().wstring().c_str(), L"wb")) { std::fwrite(out.data(), 1, out.size(), f); std::fclose(f); }
    LOGI("%s gate: the left hand's turn at the %s kept (gate_turns.json): every dock there sits the same from now on", TAG, key.c_str());
}
Quat dock_turn(const char* where, const Quat& now_turn) {
    const std::string key = g_id + " " + where;
    Quat q;
    if (kept_turn(key, q)) return q;
    keep_turn(key, now_turn);
    return now_turn;
}

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
    const Quat lturn = dock_turn("drum", g_have_left_turn ? g_grip_left_turn : qnorm(qmul(ig.q, lt0.q)));
    g_left_in_gun = {cyl_in_gun + g_left_off, lturn};
    g_right_dock_in_gun = {lid_in_gun + g_right_off, g_right_in_gun.q};
    g_left_from = lt0;
    g_left_t0 = now_s();
    g_gun_s = g0;
    g_smooth_t = -1.0f;
    g_weapon_tf = s.weapon_tf;
    g_parented = call_ptr(s.weapon_tf, "get_Parent") != nullptr;
    if (!get_v3(XFORM, s.weapon_tf, "get_LocalPosition", g_local_p) || !get_q(XFORM, s.weapon_tf, "get_LocalRotation", g_local_q)) g_parented = false;
    if (g_lift != Lift::NONE && g_lift_tf == s.weapon_tf) {   // taken while the right hand is lifted: the grip as it was before the lift
        g_gun_in_right = g_lift_gun_in_rt;
        g_right_in_gun = inverse(g_lift_gun_in_rt);
        g_right_dock_in_gun.q = g_right_in_gun.q;
        g_local_p = g_lift_local_p; g_local_q = g_lift_local_q; g_parented = g_lift_parented;
        g_lift = Lift::NONE; g_lift_u = 0.0f; g_lift_tf = nullptr;
        LOGI("%s gate: LG took the gun while the right hand was lifted: the right hand is free, its grip kept from before the lift", TAG);
    }
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

// 2026-11-02 (Tefa: "after a shot the game still rotates the drum in game's own speed, pressing LT just pushes the hammer down but
// it doesn't actually rotate the drum, so shooting speed is the same"): the game's gun (app.WeaponGunCore, read with our own
// lookup) holds the next shot behind two locks, readyShootBySequence (the shot animation done: the thumb cocking, the drum
// turning) and readyShootByTimer (ShootableTime). With the palm on the hammer and the hammer cocked by LT, both are opened
// every frame, so the next pull fires at once. Every change of the locks is logged, to see which one held it.
int g_fan_lines = 0;
int g_fan_last = -1;
// 2026-11-02 (Tefa: "can i hold RT and when i press down on the hammer it basically shoots with LG held on the hammer and LT
// pressed?"): real fanning. With RT HELD, LT cocks AND fires: for a short window the third lock (the trigger let go) is opened
// too, so the game's own shot goes off through its own path (ammo, sound, recoil); if none has gone off near the window's end,
// the game's own request (app.PlayerGun.requestShootForProcess) is asked once. Outside the window the trigger lock stays the
// game's, so a held RT never turns into full auto.
float g_fire_until = 0.0f;
int g_fire_loaded = -1;
bool g_fire_asked = false;
void request_shot() {
    MO* pg = call_ptr(player::now().updater, "get_playerGun");
    if (!is_managed(pg)) { LOGI("%s gate: fan shot: no player gun to ask", TAG); return; }
    auto* m = find_method_deep(pg->get_type_definition(), "requestShootForProcess");
    if (m == nullptr) { LOGI("%s gate: fan shot: requestShootForProcess not found", TAG); return; }
    m->call<void>(API::get()->get_vm_context(), (void*)pg, false);
    // 2026-11-02 (Tefa: "shooting works, but the muzzle don't flash"): that request fires the round only; the game has its own
    // effects-only partner (lookup: app.PlayerGun.requestShootForProcessEffectOnly), asked right after
    auto* fx = find_method_deep(pg->get_type_definition(), "requestShootForProcessEffectOnly");
    if (fx != nullptr) fx->call<void>(API::get()->get_vm_context(), (void*)pg);
    LOGI("%s gate: fan shot: the game's own shot did not go off in the window: asked it with requestShootForProcess%s", TAG, fx != nullptr ? " + its effects" : " (effects call NOT found)");
}
void fan_fire(const char* why) {
    g_fire_until = now_s() + GATE_FAN_FIRE_WINDOW_S;
    g_fire_loaded = player::loaded();
    g_fire_asked = false;
    LOGI("%s gate: fan shot (%s): the trigger lock opened for %.2f s", TAG, why, GATE_FAN_FIRE_WINDOW_S);
}
void fan_frame() {
    MO* gun = player::now().gun;
    if (gun == nullptr) return;
    bool* seq = field_ptr<bool>(gun, "readyShootBySequence");
    bool* tim = field_ptr<bool>(gun, "readyShootByTimer");
    bool* back = field_ptr<bool>(gun, "readyShootByTriggerBack");
    float* st = field_ptr<float>(gun, "ShootableTime");
    if (st != nullptr && GATE_FAN_SHOOTABLE_S > 0.0f) {
        if (g_st_orig < 0.0f || g_st_gun != gun) { g_st_orig = *st; g_st_gun = gun; LOGI("%s gate: palm on the hammer: ShootableTime %.3f -> %.3f (the game's own shot, with its flash)", TAG, *st, GATE_FAN_SHOOTABLE_S); }
        *st = GATE_FAN_SHOOTABLE_S;
    }
    const int now = (seq && *seq ? 1 : 0) | (tim && *tim ? 2 : 0) | (back && *back ? 4 : 0) | (g_cocked ? 8 : 0);
    if (now != g_fan_last && g_fan_lines < 80) {
        ++g_fan_lines;
        LOGI("%s gate: fanning: hammer %s, the game's locks: after the animation %s, timer %s (ShootableTime %.3f), trigger let go %s%s", TAG,
             g_cocked ? "cocked" : "down", seq ? (*seq ? "open" : "SHUT") : "?", tim ? (*tim ? "open" : "SHUT") : "?", st ? *st : -1.0f,
             back ? (*back ? "yes" : "no") : "?", seq == nullptr || tim == nullptr ? " (a field was not found)" : "");
        g_fan_last = now;
    }
    const float t = now_s();
    if (g_fire_until > 0.0f) {
        const int ld = player::loaded();
        if (ld >= 0 && g_fire_loaded >= 0 && ld < g_fire_loaded) { g_fire_until = 0.0f; LOGI("%s gate: fan shot went off", TAG); }
        else if (t >= g_fire_until) { g_fire_until = 0.0f; LOGI("%s gate: fan shot: nothing went off (loaded %d)", TAG, ld); }
        else if (!g_fire_asked && t >= g_fire_until - GATE_FAN_ASK_BEFORE_S && g_cocked) { g_fire_asked = true; request_shot(); }
    }
    if (!g_cocked || !GATE_FAN_OPEN_LOCKS) return;
    if (seq) *seq = true;
    if (tim) *tim = true;
    if (back && g_fire_until > 0.0f && t < g_fire_until) *back = true;   // only inside a fan shot's window
}

// 2026-11-01 23:4x (Tefa: "with the guard closed, LG puts the palm on the hammer and after every shot, LT pushes the hammer down
// again, making it possible to rapidly fire. if B is pressed while LG is held on the hammer, left hand must automatically travel
// to the drum"): LG near the hammer with the cover shut docks the left palm there; the gun stays on the right hand
bool take_hammer() {
    const auto& s = player::now();
    Pose g0{}, lt0{};
    Vec3 hp{}, lw{};
    MO* hammer = joint_by_name(s.weapon_tf, L"Hammer");
    if (hammer == nullptr || !tf_pose(s.weapon_tf, g0) || s.ik_left == nullptr || !tf_pose(target_of(s.ik_left), lt0) ||
        !get_v3(JOINT, hammer, "get_Position", hp) || !bridge::room_to_world(bridge::hand_pos(bridge::LEFT), lw)) return false;
    // 2026-11-01 23:5x: the first wear's five shots all came before a dock: LG had to be within 8 cm of the hammer. Now LG
    // anywhere with the cover shut puts the palm on it, as LG anywhere does with the cover open
    const float d = dist(lw, hp);
    const Pose ig = inverse(g0);
    const Quat lturn = dock_turn("hammer", g_have_left_turn ? g_grip_left_turn : qnorm(qmul(ig.q, lt0.q)));
    g_left_in_gun = {ig.p + rotate(ig.q, hp) + g_hammer_off, lturn};
    g_left_from = lt0;
    g_left_t0 = now_s();
    g_weapon_tf = s.weapon_tf;
    g_cocked = true;
    g_fan_lines = 0; g_fan_last = -1;
    g_hammer_cap = false;   // the thumb and the hammer read at the next render point, before any shot
    g_ham_cyl = nullptr; g_ham_turns = 0; g_ham_draw = 0.0f; g_ham_t = -1.0f;
    g_press_t0 = -1.0f;
    g_pin_lines = 0;
    g_last_loaded = player::loaded();
    LOGI("%s gate: LG at the hammer (%.3f m): the left palm on it; after each shot LT pushes it back down, B sends the hand to the drum", TAG, d);
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
            if (casing) drumrounds::eject();   // 2026-11-06: the case is seen falling out (drumrounds.h)
            shellclip::play(g_id, "round_in", shellclip::LEFT);   // 2026-11-06: the left thumb's half of the game's cycle turns the drum
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
    drumrounds::inserted();
    bridge::rumble(bridge::RIGHT, RELOAD_INSERT_BUZZ_AMP, RELOAD_INSERT_BUZZ_SEC, RELOAD_BUZZ_HZ);
    LOGI("%s gate: a round in (loaded %d, %d left in the right hand)", TAG, player::loaded(), g_rounds);
    if (g_rounds <= 0 || breech::free_chambers() <= 0) to_return(breech::free_chambers() <= 0 ? "the drum is full" : "the right hand is empty");
}

void poses() {   // this frame's gun and hands, from the left controller read once
    g_now_ok = false;
    const float now = now_s();
    if (g_phase == Phase::STAY || g_phase == Phase::HAMMER) {
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
        // 2026-11-06 (Tefa: "left hand when holding the weapon must not be frozen but move normally, frozen works with rifle but
        // it's weird when handling a single hand weapon"): the rifle's slow trail (RIGHT_RACK_LOCK_FOLLOW_SEC 0.40 s) became a
        // light smoothing of its own
        g_gun_s = GATE_HELD_FOLLOW_SEC > 0.0f ? blend(g_gun_s, mul(lc, g_gun_k), 1.0f - std::exp(-dt / GATE_HELD_FOLLOW_SEC)) : mul(lc, g_gun_k);
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

void lift_end(const char* why) {   // the gun back on its hand's own place (its local), the lift over
    if (g_lift_tf != nullptr && g_lift_parented && player::now().weapon_tf == g_lift_tf) {
        set_any(XFORM, g_lift_tf, "set_LocalPosition", &g_lift_local_p);
        set_any(XFORM, g_lift_tf, "set_LocalRotation", &g_lift_local_q);
    }
    g_lift = Lift::NONE; g_lift_u = 0.0f; g_lift_tf = nullptr; g_lift_gun_ok = false;
    LOGI("%s gate: the right hand is back on the grip (%s)", TAG, why);
}
void lift_frame(float now) {
    if (g_lift == Lift::NONE) return;
    if (player::now().weapon_tf != g_lift_tf) { g_lift = Lift::NONE; g_lift_u = 0.0f; g_lift_tf = nullptr; g_lift_gun_ok = false; return; }   // another gun: nothing written
    const float k = GATE_LIFT_SEC > 0.0f ? (now - g_lift_t0) / GATE_LIFT_SEC : 1.0f;
    if (g_lift == Lift::UP) {
        g_lift_u = std::fmin(1.0f, k);
        if (k >= 1.0f) { g_lift = Lift::HOLD; breech::open_cover("the right thumb over the hammer"); }
    } else if (g_lift == Lift::HOLD) {
        g_lift_u = 1.0f;
        if (!breech::is_open()) lift_down("the cover shut");
    } else {   // DOWN
        g_lift_u = std::fmax(0.0f, 1.0f - k);
        if (k >= 1.0f) lift_end("lift done");
    }
}
} // namespace

bool here() { return breech::cover_gun(); }
bool holding() { return g_phase == Phase::HELD || g_phase == Phase::RETURN; }
bool owns_left() { return g_phase == Phase::HELD || g_phase == Phase::RETURN || g_phase == Phase::STAY || g_phase == Phase::HAMMER || (g_phase == Phase::HANDOVER && g_ho_left); }

void tune(const Vec3& left, const Vec3& right, const Vec3& cyl_axis, const Vec3& hammer) { g_left_off = left; g_right_off = right; g_cyl_axis = cyl_axis; g_hammer_off = hammer; }
void tune_hammer(const Vec3& axis, float deg) { g_hammer_axis = axis; g_hammer_deg = deg; }
void tune_flick(const Vec3& axis, float deg) { g_flick_axis = axis; g_flick_deg = deg; }
bool hammer_down() { return g_phase == Phase::HAMMER && !g_cocked; }
bool on_hammer() { return g_phase == Phase::HAMMER; }
int left_spot() { return g_phase == Phase::HAMMER ? 10 : g_phase == Phase::STAY ? 0 : owns_left() ? 6 : 0; }   // STAY: the gun's own hold (2026-11-06)
bool right_at_cover() { return g_phase == Phase::HELD && g_rdock; }
bool gun_rot(Quat& q) {
    if (!g_now_ok || (g_phase != Phase::HELD && g_phase != Phase::RETURN && g_phase != Phase::HANDOVER)) return false;
    q = g_gun_now.q;
    return true;
}

void close_request(const char* why) { if (g_phase == Phase::HELD) to_return(why); }

void open_request(const char* why) {
    const auto& s = player::now();
    if (g_lift != Lift::NONE) return;
    if (GATE_LIFT_SEC <= 0.0f || !g_gun_in_rt_ok || s.weapon_tf == nullptr) { breech::open_cover(why); return; }
    g_lift_gun_in_rt = g_gun_in_rt;
    g_lift_tf = s.weapon_tf;
    g_lift_parented = call_ptr(s.weapon_tf, "get_Parent") != nullptr;
    if (!get_v3(XFORM, s.weapon_tf, "get_LocalPosition", g_lift_local_p) || !get_q(XFORM, s.weapon_tf, "get_LocalRotation", g_lift_local_q)) g_lift_parented = false;
    g_lift_gun_ok = false;
    g_lift = Lift::UP;
    g_lift_t0 = now_s();
    LOGI("%s gate: %s: the right thumb lifts over the hammer (%.2f s), then the cover opens", TAG, why, GATE_LIFT_SEC);
}
void lift_down(const char* why) {
    if (g_lift == Lift::NONE || g_lift == Lift::DOWN) return;
    g_lift = Lift::DOWN;
    g_lift_t0 = now_s() - (1.0f - g_lift_u) * GATE_LIFT_SEC;   // from wherever it is now
    LOGI("%s gate: %s: the cover shut, the right hand glides back onto the grip", TAG, why);
}
bool right_lifted() { return g_lift_u > 0.5f; }
void tune_lift(const Vec3& off, const Vec3& axis, float deg) { g_lift_off = off; g_lift_axis = axis; g_lift_deg = deg; }

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
    if (open && !g_was_open) {
        g_need_turn = false; g_turns = 0; g_cyl_draw = 0.0f; g_cyl_t = -1.0f;
        // 2026-11-06 (Tefa: "right thumb needs to flick the bullet guard open"): a short flick of our own (the game's cover clip
        // moves the other fingers, not the thumb); axis and size from lid_swing.json "flick_axis" / "flick_deg"
        if (GATE_FLICK_SEC > 0.0f && g_flick_deg != 0.0f)
            shellclip::pulse({L"R_Thumb1", L"R_Thumb2", L"R_Thumb3"}, g_flick_axis.x, g_flick_axis.y, g_flick_axis.z, g_flick_deg, GATE_FLICK_SEC, true);
    }
    // 2026-11-06 (Tefa: "thumb flicks it the right way, nice! please use the same flick when closing too")
    if (!open && g_was_open && GATE_FLICK_SEC > 0.0f && g_flick_deg != 0.0f)
        shellclip::pulse({L"R_Thumb1", L"R_Thumb2", L"R_Thumb3"}, g_flick_axis.x, g_flick_axis.y, g_flick_axis.z, g_flick_deg, GATE_FLICK_SEC, true);
    g_was_open = open;
    if (g_phase == Phase::OFF && bridge::flag(bridge::S_GRIPPING_WEAPON)) {   // remember how the left hand sits on the gun
        Pose g{}, l{};
        if (tf_pose(s.weapon_tf, g) && s.ik_left != nullptr && tf_pose(target_of(s.ik_left), l)) {
            g_grip_left_turn = qnorm(qmul(qinv(g.q), l.q)); g_have_left_turn = true;
            g_grip_left_in_gun = mul(inverse(g), l); g_have_left_hold = true;
        }
    }
    {   // the gun against the right hand's target, from matching numbers (see g_rt_ik)
        Pose g{};
        const bool on_right = g_phase == Phase::OFF || g_phase == Phase::STAY || g_phase == Phase::HAMMER;
        if (on_right && g_rt_ik_ok && tf_pose(s.weapon_tf, g)) { g_gun_in_rt = mul(inverse(g_rt_ik), g); g_gun_in_rt_ok = true; }
        else if (!on_right) g_gun_in_rt_ok = false;
    }
    const float now = now_s();
    lift_frame(now);
    switch (g_phase) {
    case Phase::OFF:
    case Phase::STAY:
    case Phase::HAMMER: {
        if (g_phase != Phase::HAMMER) st_restore();
        if (g_phase != Phase::OFF && (!lg || !play)) {
            LOGI("%s gate: LG let go: the left hand leaves the %s", TAG, g_phase == Phase::HAMMER ? "hammer" : "drum");
            st_restore();
            g_press_t0 = -1.0f;
            g_phase = Phase::OFF; g_weapon_tf = nullptr; break;
        }
        if (g_phase == Phase::HAMMER && !open) {   // a shot leaves the hammer down; LT pushes it back
            const int ld = player::loaded();
            if (g_last_loaded > 0 && ld >= 0 && ld < g_last_loaded) { g_cocked = false; LOGI("%s gate: shot: the hammer is down (LT cocks it)", TAG); }
            g_last_loaded = ld;
            if (bridge::pressed(bridge::S_LTRIG)) {
                if (g_cocked) LOGI("%s gate: LT: the hammer is already cocked (a live round ready): nothing to do", TAG);
                else if (g_press_t0 < 0.0f) { g_press_t0 = now; g_press_cocked = false; LOGI("%s gate: LT: the palm presses the hammer down", TAG); }
            }
            if (g_press_t0 >= 0.0f) {
                const float u = GATE_PRESS_SEC > 0.0f ? (now - g_press_t0) / GATE_PRESS_SEC : 1.0f;
                if (!g_press_cocked && u >= 0.5f) {   // the bottom of the press: cocked, the drum turns, RT held fires
                    g_press_cocked = true;
                    g_cocked = true;
                    ++g_ham_turns;
                    cock_sound();
                    bridge::rumble(bridge::LEFT, GATE_BUZZ_AMP, GATE_BUZZ_SEC, RELOAD_BUZZ_HZ);
                    LOGI("%s gate: the hammer is cocked, the drum turned one chamber", TAG);
                    if (bridge::held(bridge::S_RTRIG) && player::loaded() > 0) fan_fire("the press with RT held");
                }
                if (u >= 1.0f) g_press_t0 = -1.0f;
            }
            fan_frame();
            break;
        }
        if (g_phase == Phase::OFF && !open && play && bridge::pressed(bridge::S_LGRIP)) {
            if (take_hammer()) { g_phase = Phase::HAMMER; bridge::rumble(bridge::LEFT, GATE_BUZZ_AMP, GATE_BUZZ_SEC, RELOAD_BUZZ_HZ); }
            break;
        }
        if (!open || !play || !lg) break;
        // 2026-11-01 23:0x (Tefa: "when the guard is open, LG anywhere will smoothly but quickly take the left hand to the weapon
        // and freeze it in place and release the right hand"): any fresh LG, wherever the left hand is
        const bool fresh = bridge::pressed(bridge::S_LGRIP) || bridge::flag(bridge::S_GRIPPING_WEAPON) || g_phase != Phase::OFF;   // (on the drum or the hammer: B opens, the hand goes to the drum)
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
                g_pin_lines = 0;
                g_stay_from = g_left_in_gun;
                g_stay_to = g_have_left_hold ? g_grip_left_in_gun : Pose{g_left_in_gun.p + GATE_STAY_HOLD_OFF, g_left_in_gun.q};
                g_stay_t0 = now_s();
                LOGI("%s gate: the left hand leaves the drum for %s", TAG, g_have_left_hold ? "the game's own two-handed hold (as last held)" : "a guessed support place below the drum (no two-handed grip seen yet)");
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
    const auto& s = player::now();
    if (ik == s.ik_right) g_rt_ik_ok = tf_pose(target_of(ik), g_rt_ik);   // every phase: the gun's place against it (frame())
    if (ik == s.ik_right && g_lift_u > 0.0f && g_lift_tf == s.weapon_tf && (g_phase == Phase::OFF || g_phase == Phase::STAY || g_phase == Phase::HAMMER)) {
        Pose rt{};
        if (tf_pose(target_of(ik), rt)) {   // the gun stays as the controller holds it; the hand moves on it
            g_lift_gun = mul(rt, g_lift_gun_in_rt);
            g_lift_gun_ok = true;
            const Pose rt_in_gun = inverse(g_lift_gun_in_rt);
            const Pose lifted{rt_in_gun.p + g_lift_off, qnorm(qmul(axis_turn(g_lift_axis, g_lift_deg), rt_in_gun.q))};
            const Pose want = mul(g_lift_gun, blend(rt_in_gun, lifted, ease(g_lift_u)));
            player::set_pose(target_of(ik), want.p, want.q);
        }
        return;
    }
    if (g_phase == Phase::OFF || !g_now_ok) return;
    const float now = now_s();
    if (ik == s.ik_right) {
        if (g_phase == Phase::STAY || g_phase == Phase::HAMMER) return;   // the game's grip: the right hand steers
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
        Pose gun = g_gun_now;
        if (g_phase == Phase::STAY || g_phase == Phase::HAMMER) {   // pinned to the right hand's target now (see g_rt_ik)
            Pose rt{};
            if (g_lift_u > 0.0f && g_lift_gun_ok && g_lift_tf == s.weapon_tf) gun = g_lift_gun;   // the right hand is lifted: the gun as held
            else if (g_gun_in_rt_ok && tf_pose(target_of(s.ik_right), rt)) {
                gun = mul(rt, g_gun_in_rt);
                if (g_pin_lines < 3) { ++g_pin_lines; LOGI("%s gate: the left hand pinned to the right hand's aim (%s): %.3f m from the frame-start place", TAG, phase_name(g_phase), dist(gun.p, g_gun_now.p)); }
            }
        }
        Pose in_gun = g_phase == Phase::STAY ? blend(g_stay_from, g_stay_to, ease((now - g_stay_t0) / GATE_STAY_GLIDE_SEC)) : g_left_in_gun;
        if (g_phase == Phase::HAMMER) in_gun.p = in_gun.p + Vec3{0.0f, -GATE_PRESS_M * press_curve(now), 0.0f};   // the palm's press (gun's up = +y)
        Pose want = mul(gun, in_gun);
        const float k = (now - g_left_t0) / GATE_GLIDE_SEC;
        if ((g_phase == Phase::HELD || g_phase == Phase::HAMMER) && k < 1.0f) want = blend(g_left_from, want, ease(k));
        player::set_pose(target_of(ik), want.p, want.q);
    }
}

void hold_hammer() {   // the palm on the hammer: the right thumb kept still, the hammer cocked or down by us, not the animation
    if (g_phase != Phase::HAMMER) return;
    const auto& s = player::now();
    if (!g_hammer_cap) {
        if (s.tf == nullptr || s.weapon_tf == nullptr) return;
        bool ok = true;
        for (int i = 0; i < 3; ++i) { g_thumb[i] = joint_by_name(s.tf, THUMB[i]); ok = ok && g_thumb[i] != nullptr && get_q(JOINT, g_thumb[i], "get_LocalRotation", g_thumb_q[i]); }
        g_hammer = joint_by_name(s.weapon_tf, L"Hammer");
        g_ham_cyl = joint_by_name(s.weapon_tf, L"Cylinder");
        if (g_ham_cyl != nullptr && !get_q(JOINT, g_ham_cyl, "get_LocalRotation", g_ham_cyl_q0)) g_ham_cyl = nullptr;
        LOGI("%s gate: palm on the hammer: the drum %s", TAG, g_ham_cyl ? "held by us, turned only by LT" : "NOT found: the game turns it");
        const bool hok = g_hammer != nullptr && get_q(JOINT, g_hammer, "get_LocalRotation", g_hammer_cocked);
        if (!hok) g_hammer = nullptr;
        if (!ok) for (auto& t : g_thumb) t = nullptr;
        g_hammer_cap = true;
        LOGI("%s gate: palm on the hammer: right thumb %s, hammer %s (down = %.0f deg about %.2f %.2f %.2f)", TAG, ok ? "held still" : "NOT found",
             hok ? "held by us" : "NOT found", g_hammer_deg, g_hammer_axis.x, g_hammer_axis.y, g_hammer_axis.z);
    }
    for (int i = 0; i < 3; ++i) if (g_thumb[i] != nullptr) set_any(JOINT, g_thumb[i], "set_LocalRotation", &g_thumb_q[i]);
    if (g_ham_cyl != nullptr) {
        const float now = now_s(), dt = g_ham_t < 0.0f ? 0.0f : std::fmin(0.1f, now - g_ham_t);
        g_ham_t = now;
        const float want = (float)g_ham_turns, step = GATE_CYL_TURN_SEC > 0.0f ? dt / GATE_CYL_TURN_SEC : 1.0f;
        g_ham_draw = want > g_ham_draw ? std::fmin(want, g_ham_draw + step) : want;
        const int cap = player::capacity() > 0 ? player::capacity() : 5;
        Quat q = qnorm(qmul(g_ham_cyl_q0, axis_turn(g_cyl_axis, 360.0f / (float)cap * g_ham_draw)));
        set_any(JOINT, g_ham_cyl, "set_LocalRotation", &q);
    }
    if (g_hammer != nullptr) {
        Quat q = qnorm(qmul(g_hammer_cocked, axis_turn(g_hammer_axis, g_hammer_deg * press_curve(now_s()))));   // down and up with the press only
        set_any(JOINT, g_hammer, "set_LocalRotation", &q);
    }
}

void late_point() {
    write_gun();
    if (g_lift_u > 0.0f && g_lift_gun_ok && g_lift_tf != nullptr && player::now().weapon_tf == g_lift_tf &&
        g_phase != Phase::HELD && g_phase != Phase::RETURN && g_phase != Phase::HANDOVER)
        player::set_pose(g_lift_tf, g_lift_gun.p, g_lift_gun.q);
    turn_drum();
    hold_hammer();
    if (here()) drumrounds::point(g_phase == Phase::HELD && g_rounds > 0);   // 2026-11-06: the round in the right hand, the falling cases
    else drumrounds::reset("not the cover gun");
}

} // namespace vn::gate
