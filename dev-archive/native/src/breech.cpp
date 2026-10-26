// breech.cpp -- see breech.h.
#include "breech.h"
#include "bridge.h"
#include "ghosthand.h"
#include "joints.h"
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
Quat g_prev{0, 0, 0, 1};
bool g_have_prev = false;
float g_prev_t = 0.0f;
float g_rate = 0.0f;          // smoothed signed turn rate about the flick axis, degrees per second
float g_last_flip = -10.0f;
float g_peak = 0.0f;          // the biggest rate this second, for the log (how hard Tefa flicks)
bool g_spent = false;         // the GM 79 fired and its case is still in the barrel (2026-10-27)
int g_last_loaded = -1;       // rounds in the gun last frame: a drop while closed = a shot
int g_spent_n = 0;            // a revolver's spent casings still in the drum (2026-10-27)
int g_drag = 0;               // the drum dragged by hand: +1 opening, -1 closing, 0 not
float g_drag_from = 0.0f;     // where the left controller was across the gun when the drag began (m)
float g_drag_prog = 0.0f;     // how far along the drag is (0..1)
bool g_docked = false;        // the left hand is docked on the drum

const char* part() { return g_w != nullptr && g_w->breech == Breech::BREAK ? "barrel" : "cylinder"; }

void click() {   // the same chamber click as the bolt (rack.cpp)
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto f = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "sfx" / "bolt_click.wav";
    PlaySoundW(f.c_str(), nullptr, SND_FILENAME | SND_ASYNC | SND_NODEFAULT);
}

void set_open(bool open, const char* why) {
    if (open == g_open) return;
    g_open = open;
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
    if (!g_open && g_rate * open_sign >= BREECH_FLICK_DEG_S && g_w->breech == Breech::BREAK) set_open(true, "flick");
    else if (g_open && g_rate * open_sign <= -BREECH_FLICK_DEG_S) set_open(false, "flick");
}
} // namespace

bool here() { return RELOAD_ON && BREECH_ON && g_w != nullptr && g_w->breech != Breech::NONE && bridge::live(); }
bool is_open() { return here() && g_open; }
bool loading_allowed() { return !here() || g_open; }
bool blocks_fire() { return is_open(); }
bool spent() { return here() && g_w->breech == Breech::BREAK && g_spent; }

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

void drum_taken() {
    if (!cylinder()) return;
    g_docked = true;
    g_drag = 0;
    LOGI("%s breech: the left hand is on the drum (%s): %s", TAG, g_open ? "open" : "closed",
         g_open ? "LT puts a round in, LT when full takes the drum to push it shut" : "hold LT and drag it out to the left to open it");
}

void drum_dock_frame(bool lt_pressed, bool lt_held) {
    if (!cylinder() || !g_docked) return;
    const float x = across();
    if (g_drag != 0) {   // a drag in progress: out to the left opens, back to the right shuts
        g_drag_prog = std::fmax(0.0f, (g_drag > 0 ? g_drag_from - x : x - g_drag_from) / DRUM_DRAG_M);
        if (g_drag_prog >= 1.0f) { set_open(g_drag > 0, g_drag > 0 ? "dragged open" : "pushed shut"); g_drag = 0; return; }
        if (g_drag > 0 && !lt_held) { LOGI("%s breech: LT let go before the drum clicked open (%.0f%%)", TAG, g_drag_prog * 100.0f); g_drag = 0; }
        return;
    }
    if (!g_open) {   // closed: LG + LT on the drum takes it; dragging it out opens it
        if (lt_held) { g_drag = 1; g_drag_from = x; g_drag_prog = 0.0f; LOGI("%s breech: drum taken: drag it out to the left until it clicks", TAG); }
        return;
    }
    if (!lt_pressed) return;
    if (reload::rounds_in_hand() > 0) {   // a round from the hand into the drum
        if (reload::insert_from_hand()) {
            bridge::rumble(bridge::LEFT, RELOAD_INSERT_BUZZ_AMP, RELOAD_INSERT_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s breech: a round into the drum (%d loaded, %d left in the hand)", TAG, player::loaded(), reload::rounds_in_hand());
        }
        return;
    }
    if (free_chambers() == 0) {   // full: one more LT takes the drum, pushed back to the right it clicks shut
        g_drag = -1; g_drag_from = x; g_drag_prog = 0.0f;
        LOGI("%s breech: drum full and taken: push it to the right until it clicks (or let go past half to swing it shut)", TAG);
        return;
    }
    bridge::rumble(bridge::LEFT, RELOAD_DENY_BUZZ_AMP, RELOAD_DENY_BUZZ_SEC, RELOAD_BUZZ_HZ);
    LOGI("%s breech: LT on the open drum with no round in the hand (%d free): take rounds from the ammo pouch", TAG, free_chambers());
}

void drum_undock() {
    if (!cylinder() || !g_docked) return;
    g_docked = false;
    // let go: past half a closing push, or right after the drum was filled, it swings shut
    if (g_open && ((g_drag < 0 && g_drag_prog >= DRUM_SWING_SHARE) || (g_drag == 0 && free_chambers() == 0)))
        set_open(false, g_drag < 0 ? "let go past half: swung shut" : "let go full: swung shut");
    g_drag = 0;
}

int free_chambers() {
    if (!cylinder()) return -1;
    const int cap = player::capacity(), ld = player::loaded();
    if (cap <= 0 || ld < 0) return 0;
    return std::max(0, cap - ld - g_spent_n);
}
int spent_casings() { return cylinder() ? g_spent_n : 0; }

void insert_lt() {
    if (!here() || g_w->breech != Breech::BREAK) return;
    if (!g_open) {
        bridge::rumble(bridge::LEFT, RELOAD_DENY_BUZZ_AMP, RELOAD_DENY_BUZZ_SEC, RELOAD_BUZZ_HZ);
        LOGI("%s breech: LT at the insert point: the barrel is closed: open it first", TAG);
        return;
    }
    if (g_spent) {
        g_spent = false;
        bridge::sfx(bridge::SFX_MAG_OUT);
        bridge::rumble(bridge::LEFT, RELOAD_GRAB_BUZZ_AMP, RELOAD_GRAB_BUZZ_SEC, RELOAD_BUZZ_HZ);
        LOGI("%s breech: the spent case is out", TAG);
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
        g_spent = false;
        g_last_loaded = -1;
        g_spent_n = 0;
        g_drag = 0;
        g_docked = false;
        g_have_prev = false;
        g_rate = 0.0f;
        if (here()) LOGI("%s breech: %s (%s) opens to load: right B or a flick (%s)", TAG, id.c_str(), weapons::name(id),
                         g_w->breech == Breech::BREAK ? "muzzle down = open, up = closed" : "roll left = open, right = closed");
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
    if (g_w->breech == Breech::CYLINDER && g_open && g_spent_n > 0 && muzzle_up()) {
        LOGI("%s breech: tipped muzzle-up: %d spent casing(s) fall out, %d live round(s) stay", TAG, g_spent_n, ld);
        g_spent_n = 0;
        bridge::sfx(bridge::SFX_MAG_OUT);
        bridge::rumble(bridge::RIGHT, BREECH_BUZZ_AMP, BREECH_BUZZ_SEC, RELOAD_BUZZ_HZ);
    }
    g_last_loaded = ld;
    // right B: the GM 79 only (2026-10-27, Tefa: "B does not open the drum")
    if (g_w->breech == Breech::BREAK && bridge::pressed(bridge::S_RB)) { set_open(!g_open, "right B"); return; }
    // the GM 79 with the left hand on its front grip: LT opens / closes it (2026-10-27)
    if (g_w->breech == Breech::BREAK && bridge::flag(bridge::S_GRIPPING_WEAPON) && bridge::held(bridge::S_LGRIP) && bridge::pressed(bridge::S_LTRIG)) {
        set_open(!g_open, "LT with the left hand on the front");
        return;
    }
    if (BREECH_FLICK_ON) flick();
}

} // namespace vn::breech
