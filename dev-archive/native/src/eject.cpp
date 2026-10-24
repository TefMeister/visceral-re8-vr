// eject.cpp -- see eject.h
#include "eject.h"
#include "common.h"
#include "player.h"
#include "reload.h"
#include "settings.h"
#include "weapons.h"

#include <atomic>

namespace vn::eject {

using namespace vn::settings;

namespace {
std::atomic<bool> g_waiting{false};   // a shot since the last pump / bolt: a spent case is in the gun
thread_local bool t_ours = false;     // our own ejectCartridge call is under way: let it through
std::atomic<int> g_skipped{0};
int g_thrown = 0;

bool hand_cycled() {   // the gun in hand is a pump / bolt gun the left hand works (VR, reload by hand on)
    if (!EJECT_BY_HAND || !reload::managed_now()) return false;
    const auto* w = weapons::find(weapons::canonical(player::now().weapon_id));
    return w != nullptr && (w->pump || w->bolt);
}

int pre_eject(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    if (t_ours || argc < 2 || argv[1] == nullptr) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    const auto& s = player::now();
    auto* self = (MO*)argv[1];
    if (self != s.gun && self != s.weapon) return REFRAMEWORK_HOOK_CALL_ORIGINAL;   // not the player's gun
    if (!hand_cycled()) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    const int n = ++g_skipped;
    if (n <= 5 || n % 200 == 0) LOGI("%s eject: the game's shell throw at the shot skipped (#%d): it waits for the hand", TAG, n);
    return REFRAMEWORK_HOOK_SKIP_ORIGINAL;
}
} // namespace

void install() {
    if (!EJECT_BY_HAND) return;
    auto* m = API::get()->tdb()->find_method("app.WeaponCore", "ejectCartridge");
    if (m == nullptr) { LOGW("%s eject: app.WeaponCore.ejectCartridge NOT FOUND: the shell still flies at the shot", TAG); return; }
    m->add_hook(pre_eject, nullptr, false);
    LOGI("%s eject: hooked app.WeaponCore.ejectCartridge (pump / bolt guns: the shell leaves with the hand)", TAG);
}

void on_shot() { if (hand_cycled()) g_waiting = true; }

void by_hand() {
    if (!g_waiting.exchange(false) || !hand_cycled()) return;
    MO* gun = player::now().gun;
    if (!is_managed(gun)) return;
    t_ours = true;
    call_direct<void*>(gun, "ejectCartridge", nullptr);
    t_ours = false;
    if (++g_thrown <= 5) LOGI("%s eject: shell thrown by the hand (#%d)", TAG, g_thrown);
}

void reset() { g_waiting = false; }

} // namespace vn::eject
