// breech.cpp -- see breech.h.
#include "breech.h"
#include "bridge.h"
#include "gate.h"
#include "ghosthand.h"
#include "joints.h"
#include "json_mini.h"
#include "player.h"
#include "reload.h"
#include "settings.h"
#include "weapons.h"

#include <windows.h>
#include <mmsystem.h>

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <string>

namespace vn::breech {

using namespace settings;
using joints::now_s;
using weapons::Breech;

namespace {
const weapons::Weapon* g_w = nullptr;
std::string g_id;
bool g_open = false;
bool g_lt_wait = false;
bool g_loading = false;        // 2026-11-01: rounds are going in by LT: the hand sits at the loading place
float g_load_blend = 0.0f, g_load_t = -1.0f;        // 2026-11-01: closed by LT: LT let go before it can open the drum again
Vec3 g_lid_axis = LID_AXIS;    // 2026-11-01 22:4x: the M1851's cover swing, from lid_swing.json when present
float g_lid_deg = LID_OPEN_DEG, g_lid_sec = LID_SWING_SEC;
MO* g_carrier = nullptr;       // 2026-11-01: the GM 79's barrel joint (the M1851's "Lid"), its rest turn, and how far it is swung open (0..1)
Quat g_carrier_rest{0, 0, 0, 1};
bool g_carrier_ok = false;
float g_swing = 0.0f, g_swing_t = -1.0f;
Quat g_prev{0, 0, 0, 1};
bool g_have_prev = false;
float g_prev_t = 0.0f;
float g_rate = 0.0f;          // smoothed signed turn rate about the flick axis, degrees per second
float g_last_flip = -10.0f;
float g_peak = 0.0f;          // the biggest rate this second, for the log (how hard Tefa flicks)
bool g_spent = false;         // the GM 79 fired and its case is still in the barrel (2026-10-27)
bool g_spent_in_hand = false; // 2026-11-02: the spent case taken out is held in the left hand until LG lets go (thrown away)
bool g_hold_round = false;    // 2026-11-02: a round just went into the open barrel by hand: the hand stays on it while LG is held
int g_last_loaded = -1;       // rounds in the gun last frame: a drop while closed = a shot
int g_spent_n = 0;            // a revolver's spent casings still in the drum (2026-10-27)
int g_drag = 0;               // the drum dragged by hand: +1 opening, -1 closing, 0 not
float g_drag_from = 0.0f;     // where the left controller was across the gun when the drag began (m)
float g_drag_prog = 0.0f;     // how far along the drag is (0..1)
bool g_docked = false;        // the left hand is docked on the drum
Vec3 g_sw_from{};             // the swing to close: where the gun hand was when the window began (seen from the headset's facing)
float g_sw_t = -10.0f, g_sw_cool = -10.0f;

bool gate_gun() { return g_w != nullptr && g_w->breech == Breech::CYLINDER && g_id == GATE_GUN; }
const char* part() { return g_w != nullptr && g_w->breech == Breech::BREAK ? "barrel" : gate_gun() ? "loading cover" : "cylinder"; }

void load_lid_tune() {   // re-read each time the cover opens, so the swing can be tuned while the game runs
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto f = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "lid_swing.json";
    json::Value v;
    if (!json::load_file(f.wstring(), v)) return;
    if (const auto* a = v.get("axis"); a != nullptr && a->kind == json::Value::ARR && a->arr.size() == 3) {
        Vec3 ax{(float)a->arr[0].n, (float)a->arr[1].n, (float)a->arr[2].n};
        const float l = std::sqrt(ax.x * ax.x + ax.y * ax.y + ax.z * ax.z);
        if (l > 1e-4f) g_lid_axis = ax * (1.0f / l);
    }
    if (const auto* d = v.get("deg"); d != nullptr && d->kind == json::Value::NUM) g_lid_deg = (float)d->n;
    if (const auto* s = v.get("sec"); s != nullptr && s->kind == json::Value::NUM) g_lid_sec = (float)s->n;
    auto v3 = [&](const char* k, Vec3 d) {
        const auto* a = v.get(k);
        return (a != nullptr && a->kind == json::Value::ARR && a->arr.size() == 3) ? Vec3{(float)a->arr[0].n, (float)a->arr[1].n, (float)a->arr[2].n} : d;
    };
    const Vec3 left = v3("left", GATE_LEFT_OFF), right = v3("right", GATE_RIGHT_OFF), cyl = v3("cyl_axis", GATE_CYL_AXIS), hammer = v3("hammer", GATE_HAMMER_OFF);
    gate::tune(left, right, cyl, hammer);
    {
        const auto* hd = v.get("hammer_deg");
        gate::tune_hammer(v3("hammer_axis", GATE_HAMMER_AXIS), hd != nullptr && hd->kind == json::Value::NUM ? (float)hd->n : GATE_HAMMER_DOWN_DEG);
    }
    LOGI("%s breech: lid_swing.json: axis (%.2f %.2f %.2f), %.0f deg, %.2f s; left hand (%.3f %.3f %.3f), right hand (%.3f %.3f %.3f), drum axis (%.2f %.2f %.2f)", TAG,
         g_lid_axis.x, g_lid_axis.y, g_lid_axis.z, g_lid_deg, g_lid_sec, left.x, left.y, left.z, right.x, right.y, right.z, cyl.x, cyl.y, cyl.z);
}

void click() {   // the same chamber click as the bolt (rack.cpp)
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto f = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "sfx" / "bolt_click.wav";
    PlaySoundW(f.c_str(), nullptr, SND_FILENAME | SND_ASYNC | SND_NODEFAULT);
}

void set_open(bool open, const char* why) {
    if (open == g_open) return;
    g_open = open;
    if (open && gate_gun()) load_lid_tune();
    g_last_flip = now_s();
    click();
    bridge::rumble(bridge::RIGHT, BREECH_BUZZ_AMP, BREECH_BUZZ_SEC, RELOAD_BUZZ_HZ);
    ghosthand::event("breech", open ? "start" : "done");
    LOGI("%s breech: %s %s %s (%s), loaded %d", TAG, g_id.c_str(), part(), open ? "OPEN" : "closed", why, player::loaded());
}

// the right controller's turn since the last frame, about its own axis: X = pitch (+ = muzzle up, since the controller
// points along -Z), Z = roll (+ = the top tilts to the left, seen from behind the gun)
float turn_rate() {
    const Quat q = bridge::view_quat(bridge::S_RROT);
    const float now = now_s();
    if (!bridge::has(q.x)) { g_have_prev = false; return 0.0f; }
    const Quat qn = qnorm(q);
    float rate = 0.0f;
    const float dt = now - g_prev_t;
    if (g_have_prev && dt > 0.001f && dt < 0.1f) {
        Quat d = qnorm(qmul(qinv(g_prev), qn));       // the turn in the controller's own frame
        if (d.w < 0.0f) d = Quat{-d.x, -d.y, -d.z, -d.w};
        const float s = std::sqrt(d.x * d.x + d.y * d.y + d.z * d.z);
        const float angle = 2.0f * std::atan2(s, d.w);   // radians
        if (s > 1e-6f) {
            const float axis = (g_w->breech == Breech::BREAK ? d.x : d.z) / s;
            rate = axis * angle / dt * 57.29578f;
        }
    }
    g_prev = qn;
    g_prev_t = now;
    g_have_prev = true;
    return rate;
}

void flick() {
    const float raw = turn_rate();
    g_rate = g_rate + (raw - g_rate) * BREECH_FLICK_FOLLOW;
    if (std::fabs(g_rate) > std::fabs(g_peak)) g_peak = g_rate;
    static float told = 0.0f;
    const float now = now_s();
    if (now - told > 1.0f) {
        if (std::fabs(g_peak) >= BREECH_FLICK_LOG_DEG_S) LOGI("%s breech: fastest %s turn this second %.0f deg/s (flick needs %.0f)", TAG, g_w->breech == Breech::BREAK ? "pitch" : "roll", g_peak, BREECH_FLICK_DEG_S);
        told = now;
        g_peak = 0.0f;
    }
    if (now - g_last_flip < BREECH_FLICK_COOLDOWN_SEC) return;
    // revolver: rolled left (+) opens, right (-) closes; break action: muzzle down (-) opens, up (+) closes
    const float open_sign = g_w->breech == Breech::BREAK ? -1.0f : 1.0f;
    // 2026-10-27 (Tefa: "B does not open the drum, only LG at the drum does"): a flick only closes a revolver
    // 2026-11-01 (Tefa: "only LG + LT on the front grip to open, to close LG + LT on the front grip or a flick upwards"): a flick
    // only closes the GM 79 too; opening is the left hand's alone
    if (g_open && g_rate * open_sign <= -BREECH_FLICK_DEG_S) set_open(false, "flick");
}
} // namespace

bool here() { return RELOAD_ON && BREECH_ON && g_w != nullptr && g_w->breech != Breech::NONE && bridge::live(); }
bool is_open() { return here() && g_open; }
bool loading_allowed() { return !here() || g_open; }
bool blocks_fire() { return is_open(); }
bool spent() { return here() && g_w->breech == Breech::BREAK && g_spent; }
bool spent_in_hand() { return here() && g_w->breech == Breech::BREAK && g_spent_in_hand; }
bool hold_round() { return here() && g_w->breech == Breech::BREAK && g_open && g_hold_round; }

// the left controller across the gun: its sideways offset from the right controller, in the right controller's own axes
// (+ = to the gun's right). The drum swings out to the left
float across() {
    const Quat r = bridge::view_quat(bridge::S_RROT);
    if (!bridge::has(r.x)) return 0.0f;
    const Vec3 d = bridge::hand_pos(bridge::LEFT) - bridge::hand_pos(bridge::RIGHT);
    return rotate(qinv(qnorm(r)), d).x;
}
bool muzzle_up() {
    const Quat r = bridge::view_quat(bridge::S_RROT);
    if (!bridge::has(r.x)) return false;
    const Vec3 f = rotate(qnorm(r), Vec3{0, 0, -1});
    return f.y >= std::sin(DRUM_TILT_DEG / 57.29578f);
}
bool cylinder() { return here() && g_w->breech == Breech::CYLINDER; }

// Andyalpa's close gesture (re7_vr_reload_ext.lua try_close_motion): the right controller's move over a short window, seen
// from where the headset faces (x right, y up), a quick swipe right or a kick up
void swing_close() {
    const float now = now_s();
    if (now < g_sw_cool) return;
    const Quat h = bridge::hmd_rot();
    Vec3 f = rotate(h, Vec3{0, 0, -1});
    f.y = 0;
    const float fl = std::sqrt(f.x * f.x + f.z * f.z);
    if (fl < 1e-4f) return;
    f = f * (1.0f / fl);
    const Vec3 rt{-f.z, 0, f.x};                       // the headset's right, level
    const Vec3 p = bridge::hand_pos(bridge::RIGHT);
    const Vec3 pv{p.x * rt.x + p.z * rt.z, p.y, p.x * f.x + p.z * f.z};
    if (now - g_sw_t > SWING_WINDOW_MAX_S) { g_sw_from = pv; g_sw_t = now; return; }
    const float dt = now - g_sw_t;
    if (dt < SWING_WINDOW_MIN_S) return;
    const float dx = pv.x - g_sw_from.x, dy = pv.y - g_sw_from.y, dz = pv.z - g_sw_from.z;
    const float total = std::sqrt(dx * dx + dy * dy + dz * dz), horiz = std::sqrt(dx * dx + dz * dz);
    if (total < 1e-6f) return;
    const bool right = dx >= SWING_RIGHT_M && dx / dt >= SWING_RIGHT_MS && horiz > 1e-6f && std::fabs(dx) / horiz >= SWING_RIGHT_RATIO
                       && dx >= std::fabs(dy) && std::fabs(dy) / total <= SWING_RIGHT_MAX_UP;
    const bool up = dy >= SWING_UP_M && dy / dt >= SWING_UP_MS && dy / total >= SWING_UP_RATIO && dy >= horiz;
    if (!right && !up) return;
    g_sw_cool = now + SWING_COOLDOWN_S;
    g_sw_t = -10.0f;
    set_open(false, right ? "swung right" : "kicked up");
}

void drum_taken() {
    if (!cylinder()) return;
    g_docked = true;
    g_drag = 0;
    LOGI("%s breech: the left hand is on the %s (%s): %s", TAG, gate_gun() ? "loading cover" : "drum", g_open ? "open" : "closed",
         g_open ? "rounds from the pouch go in one per LT; with none in the hand, LT closes it"
                : gate_gun() ? "right B opens the cover" : "hold LT and drag it out to the left to open it");
}

void drum_dock_frame(bool lt_pressed, bool lt_held) {
    if (!cylinder() || !g_docked) return;
    {   // ease the hand between the drum and the loading place
        const float now = now_s(), dt = g_load_t < 0 ? 0.0f : std::fmin(0.1f, now - g_load_t);
        g_load_t = now;
        const float step = dt / DRUM_LOAD_EASE_SEC, want = (g_open && g_loading) ? 1.0f : 0.0f;
        g_load_blend = want > g_load_blend ? std::fmin(want, g_load_blend + step) : std::fmax(want, g_load_blend - step);
    }
    const float x = across();
    if (g_drag != 0) {   // a drag in progress: out to the left opens, back to the right shuts
        g_drag_prog = std::fmax(0.0f, (g_drag > 0 ? g_drag_from - x : x - g_drag_from) / DRUM_DRAG_M);
        if (g_drag_prog >= 1.0f) { set_open(g_drag > 0, g_drag > 0 ? "dragged open" : "pushed shut"); g_drag = 0; return; }
        if (g_drag > 0 && !lt_held) { LOGI("%s breech: LT let go before the drum clicked open (%.0f%%)", TAG, g_drag_prog * 100.0f); g_drag = 0; }
        return;
    }
    if (gate_gun()) return;   // 2026-11-01 22:5x: the M1851 is loaded by gate.cpp (the right hand), not by this dock
    if (!g_open) {   // closed: LG + LT on the drum takes it; dragging it out opens it
        if (!lt_held) g_lt_wait = false;
        if (lt_held && !g_lt_wait) { g_drag = 1; g_drag_from = x; g_drag_prog = 0.0f; LOGI("%s breech: drum taken: drag it out to the left until it clicks", TAG); }
        return;
    }
    if (!lt_pressed) return;
    if (reload::rounds_in_hand() > 0 && free_chambers() > 0) {   // a round from the hand into the drum (full: LT closes, below)
        if (reload::insert_from_hand()) {
            g_loading = true;   // 2026-11-01: the hand sits at the loading place while rounds go in
            bridge::rumble(bridge::LEFT, RELOAD_INSERT_BUZZ_AMP, RELOAD_INSERT_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s breech: a round into the drum (%d loaded, %d left in the hand)", TAG, player::loaded(), reload::rounds_in_hand());
            if (reload::rounds_in_hand() == 0 || free_chambers() == 0) {
                g_loading = false;
                LOGI("%s breech: %s: the hand goes back on the drum; one more LT closes it", TAG, free_chambers() == 0 ? "drum full" : "no rounds left in the hand");
            }
        }
        return;
    }
    // 2026-11-01 21:1x (Tefa: "please leave only the trip to pouch one, not just hand on the drum without the trip. still keep
    // the hand movement please and of course the LT until all bullets are in"): rounds come ONLY from the pouch (b039's LT
    // straight from the carried ammo is gone); LT on the open drum with nothing in the hand closes it
    g_loading = false;
    set_open(false, "LG + LT on the drum");
    g_lt_wait = true;   // the same LT press must not take the drum to open it again
}

void drum_undock() {
    if (!cylinder() || !g_docked) return;
    g_docked = false;
    g_loading = false; g_load_blend = 0.0f; g_load_t = -1.0f;
    // let go: the drum stays where it is; the gun hand's swing (right, or up) closes it (2026-10-27, Tefa)
    if (g_open) LOGI("%s breech: hand off the drum: swing the gun hand right or up to close it", TAG);
    g_drag = 0;
}

float drum_load_blend() { return (cylinder() && g_docked) ? g_load_blend : 0.0f; }

int free_chambers() {
    if (!cylinder()) return -1;
    const int cap = player::capacity(), ld = player::loaded();
    if (cap <= 0 || ld < 0) return 0;
    if (gate_gun()) return std::max(0, cap - ld);   // the M1851: the casings fall out as the drum turns (gate.cpp)
    return std::max(0, cap - ld - g_spent_n);
}
int spent_casings() { return cylinder() ? g_spent_n : 0; }
bool cover_gun() { return here() && gate_gun(); }
void close_cover(const char* why) { if (cover_gun()) { set_open(false, why); g_spent_n = 0; } }
bool drop_casing() { if (!cover_gun() || g_spent_n <= 0) return false; --g_spent_n; return true; }

void insert_lt() {
    if (!here() || g_w->breech != Breech::BREAK) return;
    if (!g_open) {
        bridge::rumble(bridge::LEFT, RELOAD_DENY_BUZZ_AMP, RELOAD_DENY_BUZZ_SEC, RELOAD_BUZZ_HZ);
        LOGI("%s breech: LT at the insert point: the barrel is closed: open it first", TAG);
        return;
    }
    if (g_spent) {   // 2026-11-02 (Tefa): it comes out INTO the left hand; with a live round already in the hand, one LT swaps them
        g_spent = false;
        g_spent_in_hand = true;
        bridge::sfx(bridge::SFX_MAG_OUT);
        bridge::rumble(bridge::LEFT, RELOAD_GRAB_BUZZ_AMP, RELOAD_GRAB_BUZZ_SEC, RELOAD_BUZZ_HZ);
        if (reload::round_in_hand() && reload::insert_from_hand()) {
            g_last_loaded = player::loaded();
            g_hold_round = true;
            LOGI("%s breech: LT swapped them: the spent case out into the hand, the live round in (loaded %d); LG let go drops the case", TAG, player::loaded());
        } else {
            LOGI("%s breech: the spent case is out, in the left hand: let go to throw it away, or keep LG held to the pouch for a live round", TAG);
        }
        return;
    }
    const int have = player::loaded();
    if (have <= 0) {
        bridge::rumble(bridge::LEFT, RELOAD_DENY_BUZZ_AMP, RELOAD_DENY_BUZZ_SEC, RELOAD_BUZZ_HZ);
        LOGI("%s breech: LT at the insert point: the barrel is empty", TAG);
        return;
    }
    if (!player::set_loaded(have - 1)) { LOGI("%s breech: the grenade could not be taken out (no item record)", TAG); return; }
    reload::pocket_round();   // back with the carried ammo: the next one loaded uses it first
    g_last_loaded = player::loaded();
    bridge::sfx(bridge::SFX_MAG_OUT);
    bridge::rumble(bridge::LEFT, RELOAD_GRAB_BUZZ_AMP, RELOAD_GRAB_BUZZ_SEC, RELOAD_BUZZ_HZ);
    LOGI("%s breech: a live grenade taken out (loaded %d)", TAG, player::loaded());
}

void frame() {
    const std::string id = weapons::canonical(player::now().weapon_id);
    if (id != g_id) {
        g_id = id;
        g_w = weapons::find(id);
        g_open = false;   // a gun comes out of the inventory closed
        g_carrier = nullptr; g_carrier_ok = false; g_swing = 0.0f; g_swing_t = -1.0f;
        g_spent = false;
        g_spent_in_hand = false;
        g_hold_round = false;
        g_last_loaded = -1;
        g_spent_n = 0;
        g_drag = 0;
        g_docked = false;
        g_have_prev = false;
        g_rate = 0.0f;
        if (here()) LOGI("%s breech: %s (%s) %s", TAG, id.c_str(), weapons::name(id),
                         g_w->breech == Breech::BREAK ? "opens with LG + LT on its front grip; closes the same way or with a flick up"
                         : gate_gun() ? "right B opens the loading cover; LG on it + LT puts pouch rounds in; LT with none in the hand, or right B, closes it"
                                      : "opens with LG at the drum and a drag; closes with a swing of the gun hand or LT with none in the hand");
    }
    if (!here()) return;
    if (!bridge::flag(bridge::S_CAN_USE_HANDS) || bridge::flag(bridge::S_CUTSCENE)) { g_have_prev = false; return; }
    // the GM 79 fired: its case stays in the barrel until LG + LT at the insert point takes it out
    const int ld = player::loaded();
    if (g_w->breech == Breech::BREAK && !g_open && g_last_loaded > 0 && ld >= 0 && ld < g_last_loaded) {
        g_spent = true;
        LOGI("%s breech: GM 79 fired: the spent case stays in until taken out (LG + LT at the insert point)", TAG);
    }
    // a revolver fired: the casing stays in its chamber until the open drum is tipped muzzle-up
    if (g_w->breech == Breech::CYLINDER && !g_open && g_last_loaded > 0 && ld >= 0 && ld < g_last_loaded) g_spent_n += g_last_loaded - ld;
    if (g_w->breech == Breech::CYLINDER && g_open && g_spent_n > 0 && muzzle_up() && !gate_gun()) {   // (the M1851: each LT turn drops one)
        LOGI("%s breech: tipped muzzle-up: %d spent casing(s) fall out, %d live round(s) stay", TAG, g_spent_n, ld);
        g_spent_n = 0;
        bridge::sfx(bridge::SFX_MAG_OUT);
        bridge::rumble(bridge::RIGHT, BREECH_BUZZ_AMP, BREECH_BUZZ_SEC, RELOAD_BUZZ_HZ);
    }
    if (g_w->breech == Breech::BREAK && g_open && ld > g_last_loaded && g_last_loaded >= 0 && bridge::held(bridge::S_LGRIP)) g_hold_round = true;
    g_last_loaded = ld;
    // 2026-11-02 (Tefa's three ways): the spent case held in the left hand; LG let go throws it away; LG held into the pouch
    // also takes a live round (a buzz says so), which then goes in by itself at the open barrel (nothing is in it)
    if (g_spent_in_hand && !bridge::held(bridge::S_LGRIP)) { g_spent_in_hand = false; LOGI("%s breech: LG let go: the spent case is thrown away", TAG); }
    if (g_spent_in_hand && g_open && reload::in_pouch() && !reload::round_in_hand()) {
        reload::grab_from_pouch();
        if (reload::round_in_hand()) LOGI("%s breech: LG held to the pouch with the spent case: a live round in the hand too", TAG);
    }
    if (g_hold_round && !bridge::held(bridge::S_LGRIP)) g_hold_round = false;
    // 2026-11-01 (Tefa: "please disable B opening and closing the grenade launcher"): right B no longer opens or closes it
    // (it comes back with the semi-immersive and automatic reload modes, ideas/fresh)
    // the GM 79 with the left hand on its front grip: LT opens / closes it (2026-10-27)
    if (g_w->breech == Breech::BREAK && bridge::flag(bridge::S_GRIPPING_WEAPON) && bridge::held(bridge::S_LGRIP) && bridge::pressed(bridge::S_LTRIG)) {
        set_open(!g_open, "LT with the left hand on the front");
        return;
    }
    if (gate_gun()) {   // 2026-11-01 22:4x: right B opens the M1851's cover; gate.cpp loads it and shuts it (Tefa's plan, 22:5x)
        if (bridge::pressed(bridge::S_RB)) {
            if (gate::holding()) gate::close_request("right B");   // the right hand back to the grip first, then the thumb shuts it
            else set_open(!g_open, "right B");
        }
        return;
    }
    if (g_w->breech == Breech::CYLINDER) { if (g_open && g_drag == 0) swing_close(); return; }
    if (BREECH_FLICK_ON) flick();
}

void pose_point() {
    const bool lid = gate_gun();   // 2026-11-01 22:4x: the M1851's cover swings the same way the GM 79's barrel does
    if (!here() || (g_w->breech != Breech::BREAK && !lid)) return;
    const auto& s = player::now();
    if (g_carrier == nullptr && s.weapon_tf != nullptr) {
        g_carrier = joints::joint_by_name(s.weapon_tf, lid ? L"Lid" : L"Carrier");
        g_carrier_ok = g_carrier != nullptr && joints::get_q(joints::JOINT, g_carrier, "get_LocalRotation", g_carrier_rest);
        Vec3 lp{};
        if (g_carrier_ok) joints::get_v3(joints::JOINT, g_carrier, "get_LocalPosition", lp);
        LOGI("%s breech: %s %s joint %s (rest turn %.3f %.3f %.3f %.3f, at %.3f %.3f %.3f)", TAG, g_id.c_str(), part(),
             g_carrier_ok ? (lid ? "Lid found: it swings open with the cover" : "Carrier found: it swings open with the breech") : "NOT found: no visible swing",
             g_carrier_rest.x, g_carrier_rest.y, g_carrier_rest.z, g_carrier_rest.w, lp.x, lp.y, lp.z);
    }
    if (!g_carrier_ok) return;
    const float now = now_s();
    const float dt = g_swing_t < 0.0f ? 0.0f : std::fmin(0.1f, now - g_swing_t);
    g_swing_t = now;
    const float want = g_open ? 1.0f : 0.0f;
    const float sec = lid ? g_lid_sec : BREAK_SWING_SEC;
    const float step = sec > 0.0f ? dt / sec : 1.0f;
    g_swing = want > g_swing ? std::fmin(want, g_swing + step) : std::fmax(want, g_swing - step);
    if (g_swing <= 0.0f) return;   // shut: the animation's own pose stands
    const float h = (lid ? g_lid_deg : BREAK_OPEN_DEG) * g_swing * 3.14159265f / 360.0f, sh = std::sin(h);
    const Vec3 ax = lid ? g_lid_axis : Vec3{1, 0, 0};
    Quat q = qnorm(qmul(g_carrier_rest, Quat{ax.x * sh, ax.y * sh, ax.z * sh, std::cos(h)}));
    joints::set_any(joints::JOINT, g_carrier, "set_LocalRotation", &q);
}

} // namespace vn::breech
