// shells.cpp -- see shells.h. (2026-11-02)
#include "shells.h"

#include <algorithm>

#include "bridge.h"
#include "common.h"
#include "joints.h"
#include "player.h"
#include "reload.h"
#include "settings.h"
#include "weapons.h"

namespace vn::shells {

using namespace joints;

using namespace vn::settings;

namespace {
bool g_running = false;      // an LT press is putting the shells in, one by one
float g_next_t = 0.0f;       // when the next shell goes in
int g_done = 0;              // shells put in by this LT press
} // namespace

bool port_gun() {
    const weapons::Weapon* w = weapons::find(weapons::canonical(player::now().weapon_id));
    return w != nullptr && w->reload == weapons::Reload::ROUND && w->shape == weapons::Shape::LONG && w->breech == weapons::Breech::NONE;
}

int grab_count(int carried, int room) {
    int n = SHELLS_PER_GRAB;
    if (carried >= 0) n = std::min(n, carried);
    if (room >= 0) n = std::min(n, room);
    return std::max(0, n);
}

void dock_frame(bool lt_pressed) {
    const float now = now_s();
    if (!g_running) {
        if (!lt_pressed) return;
        if (reload::rounds_in_hand() <= 0) { LOGI("%s shells: LT at the shell port with no shells in the hand", TAG); return; }
        g_running = true;
        g_done = 0;
        g_next_t = now;   // the first one at once
        LOGI("%s shells: LT at the shell port: %d shell(s) go in", TAG, reload::rounds_in_hand());
    }
    if (now < g_next_t) return;
    const int before = reload::rounds_in_hand();
    if (before <= 0 || !reload::insert_from_hand()) {   // the hand is empty, or the gun is full
        g_running = false;
        LOGI("%s shells: done: %d in by this LT press, %d left in the hand, loaded %d", TAG, g_done, reload::rounds_in_hand(), player::loaded());
        return;
    }
    ++g_done;
    bridge::rumble(bridge::LEFT, RELOAD_INSERT_BUZZ_AMP, RELOAD_INSERT_BUZZ_SEC, RELOAD_BUZZ_HZ);
    g_next_t = now + SHELLS_STEP_S;   // the next waits for the finger movement of this one
}

void undock() {
    if (g_running) LOGI("%s shells: the hand left the shell port mid-load (%d went in)", TAG, g_done);
    g_running = false;
}

} // namespace vn::shells
