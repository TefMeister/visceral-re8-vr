// breech.cpp -- see breech.h.
#include "breech.h"
#include "pairs.h"
#include "zones.h"
#include "bridge.h"
#include "drumrounds.h"
#include "gate.h"
#include "ghosthand.h"
#include "joints.h"
#include "json_mini.h"
#include "player.h"
#include "reload.h"
#include "settings.h"
#include "timings.h"
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
// 2026-11-23 (b152, Tefa's design for the GM 79): "right thumb flicking the grenade launcher lock open with B, then flick down after
// opens the launcher, flick up closes it and closes the latch with the barrel closing - to open with LG + LT, B is needed to first
// open the latch, then LG+LT makes it openable, and openable with motion - LG from the bottom puts the hand on the weapon from
// below - LG on the top puts hand on the top, only when latch is opened with B, and can push the launcher open that way with LG+LT
// again. it's gravity based so letting go of LG mid pull/push open just lets go of the barrel and it falls down".
// g_ang: how far the barrel hangs open (0 shut .. 1 fully); the left hand moves it while LG + LT are held on the barrel with the
// latch open (the hand's way down from the gun hand, over BREAK_LEVER_M); let go part way, it falls open (BREAK_FALL_PER_S2).
bool g_latch = false;            // the latch is open (right B, the barrel shut)
float g_ang = 0.0f, g_ang_v = 0.0f, g_ang_t = -1.0f;
bool g_was_part_open = false;
// 2026-11-23 (Tefa: "please add a thumb flick to grenade launcher open like wolfsbane does"): right B sends the thumb onto the latch
// (the right hand's spot 5, a Hand Poser pose), and BREAK_LATCH_FLICK_SEC later it flicks: the latch changes, the click sounds, and the
// thumb goes to its flicked place (spot 6) for as long as the latch is open; shutting runs the same the other way
float g_flick_t = -1.0f;         // when right B started the thumb's flick (-1 = none under way)
bool g_flick_to = false;         // what the latch becomes at the flick
int g_move = 0;                  // 0 at rest, 1 the left hand moves it, 2 falling open, 3 swinging shut (a flick up)
float g_drive_ref = 0.0f, g_drive_ang0 = 0.0f;
Quat g_prev{0, 0, 0, 1};
bool g_have_prev = false;
float g_prev_t = 0.0f;
float g_rate = 0.0f;          // smoothed signed turn rate about the flick axis, degrees per second
float g_last_flip = -10.0f;
float g_peak = 0.0f;          // the biggest rate this second, for the log (how hard Tefa flicks)
bool g_spent = false;         // the GM 79 fired and its case is still in the barrel (2026-10-27)
bool g_spent_in_hand = false; // 2026-11-02: the spent case taken out is held in the left hand until LG lets go (thrown away)
bool g_hold_round = false;    // 2026-11-02: a round just went into the open barrel by hand: the hand stays on it while LG is held
// b170: the spent shell pulled out by hand (settings.h BREAK_SPENT_PULL_M): 0 none, 1 the hand pulls it, 2 the hand carries the live
// one back in; how far out it is (m), the left controller where the pull began and the barrel's way out (both in the right hand
// target's frame, measure_mouth), and a one-shot "let the hand off the dock" for pairs.cpp
int g_pull = 0;
float g_pull_m = 0.0f, g_push_t0 = -1.0f;
Vec3 g_pull_c0{}, g_out_rel{0, 0, -1};
bool g_out_ok = false, g_undock_req = false;
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
        const Vec3 ry = v3("round_ypr", Vec3{DRUM_ROUND_HAND_YPR[0], DRUM_ROUND_HAND_YPR[1], DRUM_ROUND_HAND_YPR[2]});
        drumrounds::tune(ry.x, ry.y, ry.z);
        {   // 2026-11-11: the rounds lying in the right palm (drumrounds.h)
            const Vec3 po = v3("palm_off", Vec3{DRUM_PALM_OFF_CM[0], DRUM_PALM_OFF_CM[1], DRUM_PALM_OFF_CM[2]});
            const auto* ps = v.get("palm_step");
            drumrounds::tune_palm(po.x, po.y, po.z, ps != nullptr && ps->kind == json::Value::NUM ? (float)ps->n : DRUM_PALM_STEP_CM);
        }
        const auto* hs = v.get("hole_step");
        drumrounds::tune_hole(hs != nullptr && hs->kind == json::Value::NUM ? (int)hs->n : DRUM_HOLE_STEP);
        const auto* ld = v.get("lift_deg");
        gate::tune_lift(v3("lift_off", GATE_LIFT_OFF), v3("lift_axis", GATE_LIFT_AXIS), ld != nullptr && ld->kind == json::Value::NUM ? (float)ld->n : GATE_LIFT_DEG);
        const auto* fd = v.get("flick_deg");
        gate::tune_flick(v3("flick_axis", GATE_FLICK_AXIS), fd != nullptr && fd->kind == json::Value::NUM ? (float)fd->n : GATE_FLICK_DEG);
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
    // 2026-11-06 (Tefa: "old spent rounds are not coming out at all"): only shots seen while the mod watched were counted, and a
    // round only leaves a revolver by being fired, so at the opening every empty chamber holds a spent case
    if (open && cover_gun() && player::capacity() > 0 && player::loaded() >= 0) {
        const int empty = std::max(0, player::capacity() - player::loaded());
        if (empty > g_spent_n) { LOGI("%s breech: %d empty chamber(s) at the opening: each holds a spent case (%d were counted)", TAG, empty, g_spent_n); g_spent_n = empty; }
    }
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
bool blocks_fire() { return is_open() || (here() && g_w->breech == Breech::BREAK && (g_ang > 0.02f || g_latch)); }   // b152: nor with the latch open
bool latch_open() { return here() && g_w->breech == Breech::BREAK && g_latch; }
int latch_right_spot() { return !here() || g_w->breech != Breech::BREAK ? 0 : g_flick_t >= 0.0f ? 5 : g_latch ? 6 : 0; }   // the right hand's Hand Poser spot: 5 the thumb on the latch, 6 flicked open
float break_open_part() { return here() && g_w->breech == Breech::BREAK ? g_ang : 0.0f; }
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
        const float step = dt / std::fmax(0.01f, timings::v(timings::LOAD_EASE_S)), want = (g_open && g_loading) ? 1.0f : 0.0f;
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
void open_cover(const char* why) { if (cover_gun()) set_open(true, why); }
void close_cover(const char* why) { if (cover_gun()) { set_open(false, why); g_spent_n = 0; } }
bool drop_casing() { if (!cover_gun() || g_spent_n <= 0) return false; --g_spent_n; return true; }

// b170: the left controller in the right hand target's frame (the frame the barrel's way out is kept in)
bool pull_ctrl(Vec3& rel) {
    const auto& s = player::now();
    Vec3 rp, cp;
    Quat rq;
    if (!player::get_pose(field_obj(s.ik_right, "Target"), rp, rq) || !bridge::room_to_world(bridge::hand_pos(bridge::LEFT), cp)) return false;
    rel = rotate(qinv(qnorm(rq)), cp - rp);
    return true;
}
void pull_frame() {
    if (g_pull == 1) {
        if (!bridge::held(bridge::S_LGRIP) || !g_open) {
            LOGI("%s breech: the spent shell let go %.0f%% out: it slides back in", TAG, g_pull_m / BREAK_SPENT_PULL_M * 100.0f);
            g_pull = 0; g_pull_m = 0.0f;
            return;
        }
        Vec3 c;
        if (!g_out_ok || !pull_ctrl(c)) return;
        const Vec3 d = c - g_pull_c0;
        const float m = d.x * g_out_rel.x + d.y * g_out_rel.y + d.z * g_out_rel.z;
        g_pull_m = m < 0.0f ? 0.0f : m > BREAK_SPENT_PULL_M ? BREAK_SPENT_PULL_M : m;
        if (m < BREAK_SPENT_PULL_M) return;
        g_spent = false;
        g_spent_in_hand = true;
        bridge::sfx(bridge::SFX_MAG_OUT);
        bridge::rumble(bridge::LEFT, RELOAD_GRAB_BUZZ_AMP, RELOAD_GRAB_BUZZ_SEC, RELOAD_BUZZ_HZ);
        if (reload::round_in_hand()) {
            g_pull = 2; g_push_t0 = now_s();
            LOGI("%s breech: the spent shell is out, in the hand: the hand pushes the live one in (%.2f s)", TAG, BREAK_PUSH_SEC);
        } else {
            g_pull = 0; g_pull_m = 0.0f; g_undock_req = true;
            LOGI("%s breech: the spent shell is out, in the left hand: let go of LG to throw it away, or keep LG held to the pouch for a live one", TAG);
        }
        return;
    }
    if (g_pull == 2) {
        const float k = BREAK_PUSH_SEC > 0.0f ? (now_s() - g_push_t0) / BREAK_PUSH_SEC : 1.0f;
        g_pull_m = BREAK_SPENT_PULL_M * (1.0f - (k >= 1.0f ? 1.0f : k * k * (3.0f - 2.0f * k)));
        if (k < 1.0f) return;
        g_pull = 0; g_pull_m = 0.0f;
        if (reload::round_in_hand() && reload::insert_from_hand()) {
            g_last_loaded = player::loaded();
            g_hold_round = true;
            click();
            LOGI("%s breech: the live one pushed in (loaded %d); the spent shell stays in the hand until LG is let go", TAG, player::loaded());
        } else {
            LOGI("%s breech: the live one could not go in", TAG);
        }
    }
}

void insert_lt() {
    if (!here() || g_w->breech != Breech::BREAK) return;
    if (insert_on_top()) return;   // b170: the hand on top of the barrel: LT moves the barrel (break_frame), it loads nothing
    if (!g_open) {   // b152: at a barrel that is not open LT is the hand moving it (break_frame), or a refusal while the latch is shut
        if (!g_latch) {
            bridge::rumble(bridge::LEFT, RELOAD_DENY_BUZZ_AMP, RELOAD_DENY_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s breech: LT at the insert point: the latch is shut: right B first", TAG);
        }
        return;
    }
    if (g_spent) {   // b170 (was 2026-11-02: one LT took it out at once, or swapped it for the round in the hand)
        if (g_pull != 0) return;
        Vec3 c;
        if (!pull_ctrl(c)) return;
        g_pull = 1; g_pull_m = 0.0f; g_pull_c0 = c;
        bridge::rumble(bridge::LEFT, RELOAD_GRAB_BUZZ_AMP, RELOAD_GRAB_BUZZ_SEC, RELOAD_BUZZ_HZ);
        LOGI("%s breech: LT on the spent shell: thumb and finger on it; pull it out %.0f cm along the barrel (LG held)%s", TAG,
             BREAK_SPENT_PULL_M * 100.0f, reload::round_in_hand() ? "; the live one in the hand goes in after" : "");
        return;
    }
    const int have = player::loaded();
    if (have <= 0 && !reload::round_in_hand()) return;   // b168: nothing to load or take out: LT moves the barrel (break_frame)
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

// b152: the GM 79, every frame (see g_latch above)
float left_down_m() {   // how far the left controller is BELOW the gun hand, straight down (m; room space: y is up). Down is gravity's
    // way, as the barrel's fall is; the gun hand's own axes lie any way the gun is held (the first cut used them: no pull was seen)
    return bridge::hand_pos(bridge::RIGHT).y - bridge::hand_pos(bridge::LEFT).y;
}
bool left_on_barrel() { return (BREAK_FRONT_GRIP_MOVES && bridge::flag(bridge::S_GRIPPING_WEAPON)) || pairs::docked_on(zones::INSERT); }   // b170: the top hold only
void break_frame() {
    const float now = now_s();
    const float dt = g_ang_t < 0.0f ? 0.0f : std::fmin(0.05f, now - g_ang_t);
    g_ang_t = now;
    const float raw = turn_rate();
    g_rate = g_rate + (raw - g_rate) * BREECH_FLICK_FOLLOW;
    const bool shut = g_ang <= 0.001f;
    // right B: the thumb flicks the latch, only with the barrel shut
    if (bridge::pressed(bridge::S_RB)) {
        if (shut && g_flick_t < 0.0f) {
            g_flick_t = now; g_flick_to = !g_latch;
            LOGI("%s breech: right B: the thumb goes onto the latch (%.2f s), then flicks it %s", TAG, BREAK_LATCH_FLICK_SEC, g_flick_to ? "open" : "shut");
        } else if (shut) {
        } else LOGI("%s breech: right B: the latch cannot shut while the barrel hangs open (%.0f%%)", TAG, g_ang * 100.0f);
    }
    // the thumb stays on the latch for as long as B is held (at least BREAK_LATCH_FLICK_SEC) and flicks when it is let go: a short
    // press is the quick flick, a held B shows the thumb resting on the latch (which is also how its pose can be looked at and set)
    if (g_flick_t >= 0.0f && now - g_flick_t >= BREAK_LATCH_FLICK_SEC && !bridge::held(bridge::S_RB)) {
        g_flick_t = -1.0f;
        if (g_ang <= 0.001f) {
            g_latch = g_flick_to;
            click();
            bridge::rumble(bridge::RIGHT, BREECH_BUZZ_AMP, BREECH_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s breech: right B: the thumb flicks the latch %s%s", TAG, g_latch ? "OPEN" : "shut", g_latch ? ": a flick down, or LG + LT on the barrel and a pull, opens it" : "");
        }
    }
    // the left hand moves the barrel: LG + LT held on it, the latch open (not at a fully open barrel's insert point: LT loads there)
    const bool both = bridge::held(bridge::S_LGRIP) && bridge::held(bridge::S_LTRIG) && left_on_barrel();
    // b168 (Tefa 2026-11-25: "holding it from the bottom and top of the barrel and having LG and LT to be able to bend it closed
    // again"; robot: LG + LT at the open barrel's top only said "LT at the insert point: the barrel is empty"): LT loads there only
    // when there is something to load or take out; otherwise it moves the barrel like anywhere else on it
    const bool load_work = g_spent || g_hold_round || reload::round_in_hand() || player::loaded() > 0;
    // b170: the hand on TOP of the barrel always moves it; at the chamber end LT loads (insert_on_top, measure_mouth below)
    const bool at_open_insert = g_ang >= 0.999f && pairs::docked_on(zones::INSERT) && !bridge::flag(bridge::S_GRIPPING_WEAPON) && !insert_on_top() && load_work;
    if (g_move != 1 && both && bridge::pressed(bridge::S_LTRIG)) {
        if (!g_latch) {
            bridge::rumble(bridge::LEFT, RELOAD_DENY_BUZZ_AMP, RELOAD_DENY_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s breech: LG + LT on the barrel: the latch is shut: right B first", TAG);
        } else if (!at_open_insert) {
            g_move = 1; g_drive_ref = left_down_m(); g_drive_ang0 = g_ang; g_ang_v = 0.0f;
            LOGI("%s breech: LG + LT on the barrel, the latch open: the hand moves it (from %.0f%% open)", TAG, g_ang * 100.0f);
        }
    }
    if (g_move == 1) {
        if (both) {
            const float travel = BREAK_LEVER_M * BREAK_OPEN_DEG * 3.14159265f / 180.0f;   // the hand's way for the whole swing
            const float a = g_drive_ang0 + (left_down_m() - g_drive_ref) / travel;
            g_ang = a < 0.0f ? 0.0f : a > 1.0f ? 1.0f : a;
        } else if (g_ang <= BREAK_SHUT_PART) {
            g_move = 3;   // let go almost shut: it clicks shut
        } else {
            g_move = g_ang >= 0.999f ? 0 : 2; g_ang_v = 0.0f;
            if (g_move == 2) LOGI("%s breech: the barrel let go at %.0f%%: it falls open", TAG, g_ang * 100.0f);
        }
    }
    // a flick of the gun hand: down lets a latched-open barrel fall, up swings an open one shut
    if (BREECH_FLICK_ON && now - g_last_flip >= BREECH_FLICK_COOLDOWN_SEC && g_move != 1) {
        if (g_latch && shut && g_rate <= -BREECH_FLICK_DEG_S) { g_move = 2; g_ang_v = BREAK_FLICK_START_PER_S; g_last_flip = now; LOGI("%s breech: a flick down, the latch open: the barrel falls open", TAG); }
        else if (g_ang > 0.5f && g_rate >= BREECH_FLICK_DEG_S) { g_move = 3; g_last_flip = now; LOGI("%s breech: a flick up: the barrel swings shut", TAG); }
    }
    if (g_move == 2) {   // falling open
        g_ang_v += BREAK_FALL_PER_S2 * dt;
        g_ang = std::fmin(1.0f, g_ang + g_ang_v * dt);
        if (g_ang >= 1.0f) { g_move = 0; g_ang_v = 0.0f; }
    } else if (g_move == 3) {   // swinging shut
        g_ang = std::fmax(0.0f, g_ang - (BREAK_SWING_SEC > 0.0f ? dt / BREAK_SWING_SEC : 1.0f));
        if (g_ang <= 0.0f) g_move = 0;
    }
    // what the rest of the mod asks: open = hanging fully open (rounds go in, cases come out); shut = the latch shuts with it
    if (!g_open && g_ang >= 0.999f) set_open(true, "it hangs fully open");
    if (g_ang <= 0.001f && g_move != 1 && (g_open || g_was_part_open)) {
        if (g_open) set_open(false, "the barrel shut: the latch shuts with it");
        else LOGI("%s breech: the barrel shut again: the latch shuts with it", TAG);
        g_latch = false;
    }
    if (g_move != 1) g_was_part_open = g_ang > 0.001f;
    else if (g_ang > 0.001f) g_was_part_open = true;
}

void frame() {
    const std::string id = weapons::canonical(player::now().weapon_id);
    if (id != g_id) {
        g_id = id;
        g_w = weapons::find(id);
        g_open = false;   // a gun comes out of the inventory closed
        g_carrier = nullptr; g_carrier_ok = false; g_swing = 0.0f; g_swing_t = -1.0f;
        g_flick_t = -1.0f; g_latch = false; g_ang = 0.0f; g_ang_v = 0.0f; g_ang_t = -1.0f; g_move = 0; g_was_part_open = false;
        g_spent = false;
        g_spent_in_hand = false;
        g_hold_round = false;
        g_pull = 0; g_pull_m = 0.0f; g_undock_req = false;
        g_last_loaded = -1;
        g_spent_n = 0;
        g_drag = 0;
        g_docked = false;
        g_have_prev = false;
        g_rate = 0.0f;
        if (here()) LOGI("%s breech: %s (%s) %s", TAG, id.c_str(), weapons::name(id),
                         g_w->breech == Breech::BREAK ? "right B unlatches it; LG + LT on top of the barrel opens and shuts it, or a flick down / up; LT at the open chamber pulls the spent shell"
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
    if (g_w->breech == Breech::BREAK) { pull_frame(); break_frame(); return; }   // b152: the latch, the hand on the barrel, gravity
    if (gate_gun()) {   // 2026-11-01 22:4x: right B opens the M1851's cover; gate.cpp loads it and shuts it (Tefa's plan, 22:5x)
        if (bridge::pressed(bridge::S_RB)) {
            if (gate::holding()) gate::close_request("right B");   // the right hand back to the grip first, then the thumb shuts it
            else if (!g_open) gate::open_request("right B");   // 2026-11-06: the thumb lifts over the hammer first (gate.cpp)
            else { set_open(false, "right B"); gate::lift_down("right B"); }
        }
        return;
    }
    if (g_w->breech == Breech::CYLINDER) { if (g_open && g_drag == 0) swing_close(); return; }
    if (BREECH_FLICK_ON) flick();
}

// 2026-11-23 (the 360 view's list: "its `Lever` joint turning with the flick"): the GM 79's latch part itself turns when the thumb
// flicks it open and back when the latch shuts (it stood still while the thumb flicked beside it)
void lever_point() {
    static MO* tf = nullptr;
    static MO* lever = nullptr;
    static Quat rest{0, 0, 0, 1};
    static bool ok = false;
    static float k = 0.0f, last = -1.0f;
    const auto& s = player::now();
    if (s.weapon_tf != tf) {
        tf = s.weapon_tf; k = 0.0f;
        lever = tf != nullptr ? joints::joint_by_name(tf, L"Lever") : nullptr;
        ok = lever != nullptr && joints::get_q(joints::JOINT, lever, "get_LocalRotation", rest);
        LOGI("%s breech: %s latch part (Lever) %s", TAG, g_id.c_str(), ok ? "found: it turns with the flick" : "NOT found: the latch does not move");
    }
    const float now = now_s(), dt = last < 0.0f ? 0.0f : std::fmin(0.1f, now - last);
    last = now;
    const float step = BREAK_LATCH_TURN_SEC > 0.0f ? dt / BREAK_LATCH_TURN_SEC : 1.0f;
    k = g_latch ? std::fmin(1.0f, k + step) : std::fmax(0.0f, k - step);
    if (!ok || k <= 0.0f) return;
    const float h = BREAK_LATCH_DEG * k * 3.14159265f / 360.0f, sh = std::sin(h);
    Quat q = qnorm(qmul(rest, Quat{BREAK_LATCH_AXIS[0] * sh, BREAK_LATCH_AXIS[1] * sh, BREAK_LATCH_AXIS[2] * sh, std::cos(h)}));
    joints::set_any(joints::JOINT, lever, "set_LocalRotation", &q);
}

// b168 (2026-11-25, Tefa: "the shell insert point is off to the right by quite a bit"): the insert point was the right wrist plus a
// guessed (0, 5, 12 cm), never measured, and it stood still while the barrel swung. Measured live (q_gm79_insert.lua, robot, barrel
// fully open): the point 3.8 cm right of the gun's centre line, 4.7 cm under and 8.2 cm behind the barrel's chamber end
// (vfx_muzzle2, under Carrier). Now the point rides the barrel: on top of its rear while shut (BREAK_TOP_OFF, where the hand pushes
// it open), easing onto the chamber end as it opens (where the grenade goes in). Worked out after the arm is solved, in the right
// hand target's frame (the way the magazine's line is, reload.cpp measure_mag_rel), and handed to pairs.cpp next frame.
namespace {
MO* g_mouth_tf = nullptr;
MO* g_body = nullptr;
Vec3 g_carrier_lp{}, g_mouth_lp{};
bool g_mouth_joints = false;
bool g_mouth_ok = false;
bool g_at_mouth = false;          // b170: the dock is at the chamber end (loading), not on top of the barrel
MO* g_ammo = nullptr;             // b170: the gun's own grenade joint (Ammo01, under Carrier): the live one; its rest under the barrel
Vec3 g_ammo_lp{}, g_ammo_scale{1, 1, 1};
Quat g_ammo_lq{0, 0, 0, 1};
bool g_ammo_hidden = false;
Vec3 g_mouth_rel{};               // the insert point, in the right hand target's frame
void measure_mouth(const Quat& carrier_q) {
    const auto& s = player::now();
    if (s.weapon_tf != g_mouth_tf) {
        g_mouth_tf = s.weapon_tf; g_mouth_ok = false; g_mouth_joints = false;
        g_body = g_mouth_tf != nullptr ? joints::joint_by_name(g_mouth_tf, L"Body") : nullptr;
        MO* m = g_mouth_tf != nullptr ? joints::joint_by_name(g_mouth_tf, L"vfx_muzzle2") : nullptr;
        g_ammo = g_mouth_tf != nullptr ? joints::joint_by_name(g_mouth_tf, L"Ammo01") : nullptr;
        g_ammo_hidden = false;
        if (g_ammo == nullptr || !joints::get_v3(joints::JOINT, g_ammo, "get_LocalPosition", g_ammo_lp) || !joints::get_q(joints::JOINT, g_ammo, "get_LocalRotation", g_ammo_lq) ||
            !joints::get_v3(joints::JOINT, g_ammo, "get_LocalScale", g_ammo_scale))
            g_ammo = nullptr;
        g_mouth_joints = g_body != nullptr && g_carrier != nullptr && m != nullptr &&
                         joints::get_v3(joints::JOINT, g_carrier, "get_LocalPosition", g_carrier_lp) && joints::get_v3(joints::JOINT, m, "get_LocalPosition", g_mouth_lp);
        LOGI("%s breech: %s insert point %s (chamber end %.3f %.3f %.3f under the barrel joint)", TAG, g_id.c_str(),
             g_mouth_joints ? "rides the barrel" : "joints NOT found: the old fixed place", g_mouth_lp.x, g_mouth_lp.y, g_mouth_lp.z);
    }
    if (!g_mouth_joints) return;
    Vec3 bp, rp;
    Quat bq, rq;
    if (!joints::get_v3(joints::JOINT, g_body, "get_Position", bp) || !joints::get_q(joints::JOINT, g_body, "get_Rotation", bq) ||
        !player::get_pose(field_obj(s.ik_right, "Target"), rp, rq))
        return;
    // b170 (Tefa 2026-11-25, asked where the top hold goes: "further forward please"): the one dock has two places, both riding the
    // barrel. ON TOP of the barrel AHEAD of the hinge (BREAK_TOP_HOLD, from the barrel joint) is where the hand opens and shuts it:
    // pushed down it opens, lifted it shuts, the way a hand on a real barrel moves it. The CHAMBER END is where a grenade goes in or a
    // spent case comes out: the dock goes there only at a fully open barrel with a grenade in the hand or a case to take out. It
    // never moves while the hand is docked on it (pairs.cpp), so a hand on top rides the barrel all the way open and back.
    const bool docked = pairs::docked_on(zones::INSERT);
    if (!docked) g_at_mouth = g_ang >= 0.999f && (reload::round_in_hand() || g_spent || g_hold_round);
    const Quat cq = qnorm(carrier_q);
    // b170: the hand on the spent shell rides it out of the chamber (and back in with the live one): the dock moves g_pull_m out
    const Vec3 out_c{0.0f, 0.0f, -1.0f};   // the barrel's own way out of the chamber end (the muzzle is +z)
    const Vec3 at = g_at_mouth ? g_mouth_lp + out_c * g_pull_m : Vec3{BREAK_TOP_HOLD[0], BREAK_TOP_HOLD[1], BREAK_TOP_HOLD[2]};
    const Vec3 local = g_carrier_lp + rotate(cq, at);
    const Vec3 w = bp + rotate(qnorm(bq), local);
    const Quat inv = qinv(qnorm(rq));
    g_mouth_rel = rotate(inv, w - rp);
    g_mouth_ok = true;
    g_out_rel = rotate(inv, rotate(qnorm(bq), rotate(cq, out_c)));
    g_out_ok = true;
    // b170: the spent shell is drawn by the Lua's copy (visceral_re8_shell2.lua, slots 217-225, the gun's space): in the chamber
    // while a live one is in the hand, sliding out with the pull, then in the hand beside the live one / alone until LG lets go.
    // The gun's own grenade joint is the live one; with none in the hand or the barrel it is hidden while the copy shows
    if (g_ammo == nullptr) return;
    const bool live_in_hand = reload::round_in_hand();
    const bool spent_out = g_spent_in_hand || g_pull == 2;
    // with NO live one in the hand the gun's own grenade joint IS the spent shell: it slides out with the pull and rides in the hand
    // (written in the world after the animation, as the barrel's turn is); with a live one in the hand (the gun's joint is that one)
    // the spent shell is the Lua's copy [the copy's mesh part for the GM 79 is not found yet: it may not show]
    static bool drew_spent = false;
    const bool draw_spent = !live_in_hand && (g_pull == 1 || g_spent_in_hand);
    if (drew_spent && !draw_spent && !live_in_hand) {   // thrown away (or let back in): the joint back to its place in the barrel
        joints::set_any(joints::JOINT, g_ammo, "set_LocalPosition", &g_ammo_lp);
        joints::set_any(joints::JOINT, g_ammo, "set_LocalRotation", &g_ammo_lq);
    }
    drew_spent = draw_spent;
    if (draw_spent) {
        Vec3 lp;
        Quat lq;
        bool ok = true;
        if (g_spent_in_hand) ok = reload::round_hand_local(lp, lq);
        else { lp = g_carrier_lp + rotate(cq, g_ammo_lp + out_c * g_pull_m); lq = qnorm(qmul(cq, g_ammo_lq)); }
        if (ok) {
            const Vec3 gw = bp + rotate(qnorm(bq), lp);
            const Quat gr = qnorm(qmul(qnorm(bq), lq));
            joints::set_any(joints::JOINT, g_ammo, "set_Position", &gw);
            joints::set_any(joints::JOINT, g_ammo, "set_Rotation", &gr);
        }
    }
    const bool copy_on = live_in_hand && (g_pull != 0 || spent_out || g_spent);
    if (copy_on) {
        Vec3 cp;
        Quat cr;
        bool ok = false;
        if (spent_out) {
            ok = reload::round_hand_local(cp, cr);
            if (ok) cp = cp + rotate(qnorm(cr), Vec3{BREAK_SPENT_BESIDE[0], BREAK_SPENT_BESIDE[1], BREAK_SPENT_BESIDE[2]});
        } else {
            cp = g_carrier_lp + rotate(cq, g_ammo_lp + out_c * (g_pull == 1 ? g_pull_m : 0.0f));
            cr = qnorm(qmul(cq, g_ammo_lq));
            ok = true;
        }
        if (ok) {
            const float v[8] = {cp.x, cp.y, cp.z, cr.x, cr.y, cr.z, cr.w, 1.0f};
            for (int i = 0; i < 8; ++i) bridge::put((bridge::Slot)(bridge::S_SHELL2_POS + i), v[i]);
            bridge::put(bridge::S_SHELL2_ON, bridge::view(bridge::S_FRAME) + 1.0f);
        }
    }
    if (g_ammo_hidden) {   // (an earlier cut hid the gun's joint; nothing hides it now)
        joints::set_any(joints::JOINT, g_ammo, "set_LocalScale", &g_ammo_scale);
        g_ammo_hidden = false;
    }
}
} // namespace
bool insert_point(const Vec3& rp, const Quat& rq, Vec3& out) {
    if (!BREAK_INSERT_RIDES || !here() || g_w->breech != Breech::BREAK || !g_mouth_ok) return false;
    out = rp + rotate(qnorm(rq), g_mouth_rel);
    return true;
}
bool take_undock() { const bool r = g_undock_req; g_undock_req = false; return r; }
int spent_stage() { return !here() || g_w->breech != Breech::BREAK ? 0 : g_pull == 1 ? 1 : g_pull == 2 ? 2 : g_spent_in_hand ? 3 : 0; }
bool insert_on_top() { return BREAK_INSERT_RIDES && here() && g_w->breech == Breech::BREAK && g_mouth_ok && !g_at_mouth; }

void pose_point() {
    const bool lid = gate_gun();   // 2026-11-01 22:4x: the M1851's cover swings the same way the GM 79's barrel does
    if (!here() || (g_w->breech != Breech::BREAK && !lid)) return;
    if (!lid) lever_point();
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
    const float sec = lid ? (timings::has(timings::COVER_SWING_S) ? timings::v(timings::COVER_SWING_S) : g_lid_sec) : BREAK_SWING_SEC;   // 2026-11-07: timings.json wins over lid_swing.json when set
    const float step = sec > 0.0f ? dt / sec : 1.0f;
    g_swing = want > g_swing ? std::fmin(want, g_swing + step) : std::fmax(want, g_swing - step);
    if (!lid) g_swing = g_ang;   // b152: the GM 79's barrel hangs where the hand, the fall or the flick has it
    const float h = (lid ? g_lid_deg : BREAK_OPEN_DEG) * std::fmax(0.0f, g_swing) * 3.14159265f / 360.0f, sh = std::sin(h);
    const Vec3 ax = lid ? g_lid_axis : Vec3{1, 0, 0};
    Quat q = qnorm(qmul(g_carrier_rest, Quat{ax.x * sh, ax.y * sh, ax.z * sh, std::cos(h)}));
    if (!lid) measure_mouth(q);   // b168: the insert point rides the barrel (shut too)
    if (g_swing <= 0.0f) return;   // shut: the animation's own pose stands
    joints::set_any(joints::JOINT, g_carrier, "set_LocalRotation", &q);
}

} // namespace vn::breech
