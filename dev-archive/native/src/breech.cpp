// breech.cpp -- see breech.h.
#include "breech.h"
#include "bridge.h"
#include "ghosthand.h"
#include "joints.h"
#include "player.h"
#include "settings.h"
#include "weapons.h"

#include <windows.h>
#include <mmsystem.h>

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
    if (!g_open && g_rate * open_sign >= BREECH_FLICK_DEG_S) set_open(true, "flick");
    else if (g_open && g_rate * open_sign <= -BREECH_FLICK_DEG_S) set_open(false, "flick");
}
} // namespace

bool here() { return RELOAD_ON && BREECH_ON && g_w != nullptr && g_w->breech != Breech::NONE && bridge::live(); }
bool is_open() { return here() && g_open; }
bool loading_allowed() { return !here() || g_open; }
bool blocks_fire() { return is_open(); }

void frame() {
    const std::string id = weapons::canonical(player::now().weapon_id);
    if (id != g_id) {
        g_id = id;
        g_w = weapons::find(id);
        g_open = false;   // a gun comes out of the inventory closed
        g_have_prev = false;
        g_rate = 0.0f;
        if (here()) LOGI("%s breech: %s (%s) opens to load: right B or a flick (%s)", TAG, id.c_str(), weapons::name(id),
                         g_w->breech == Breech::BREAK ? "muzzle down = open, up = closed" : "roll left = open, right = closed");
    }
    if (!here()) return;
    if (!bridge::flag(bridge::S_CAN_USE_HANDS) || bridge::flag(bridge::S_CUTSCENE)) { g_have_prev = false; return; }
    if (bridge::pressed(bridge::S_RB)) { set_open(!g_open, "right B"); return; }
    if (BREECH_FLICK_ON) flick();
}

} // namespace vn::breech
