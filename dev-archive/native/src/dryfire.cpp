// dryfire.cpp -- see dryfire.h.
#include "dryfire.h"
#include "breech.h"
#include "bridge.h"
#include "common.h"
#include "joints.h"
#include "player.h"
#include "rack.h"
#include "reload.h"
#include "settings.h"

#include <windows.h>
#include <mmsystem.h>

#include <chrono>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <vector>

namespace vn::dryfire {
using namespace vn::settings;
namespace {
std::vector<char> g_wav;      // the click, read once
bool g_read = false;

bool load() {
    if (g_read) return !g_wav.empty();
    g_read = true;
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto f = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "sfx" / "dry_hammer.wav";   // 2026-11-01 (Tefa: "it doesn't sound like the gun click sound ... swap every empty click sound for a short one like the hammer being cocked")
    std::ifstream in(f, std::ios::binary);
    g_wav.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
    LOGI("%s dry fire: click %s (%zu bytes)", TAG, g_wav.empty() ? "NOT FOUND" : "loaded", g_wav.size());
    return !g_wav.empty();
}

const char* why_not() {   // why the gun will not fire now, or nullptr when it will
    if (rack::needed()) return "a rack is due";
    if (breech::blocks_fire()) return "it is open";
    if (reload::mag_out()) return "the magazine is out";
    if (player::loaded() == 0) return "it is empty";
    return nullptr;
}
// 2026-11-01 (Tefa: "can you see about the empty click sounds next"; the idea: "the game's own empty click on every trigger pull
// of an empty gun"): app.PlayerGun.requestShootNoneBullet(), the game's own shot with no bullet (found in the type list next to
// get_isGunShootEmpty), plays its own empty click. False when it is not there (our wav then).
bool game_dry_shot() {
    MO* pg = call_ptr(player::now().updater, "get_playerGun");
    if (!is_managed(pg)) return false;
    auto* m = find_method_deep(pg->get_type_definition(), "requestShootNoneBullet");
    if (m == nullptr) return false;
    m->call<void>(API::get()->get_vm_context(), (void*)pg);
    return true;
}
} // namespace

// 2026-11-01 (Tefa: "the game also plays an empty sound once, sometimes multiple times before going quiet, so the hammer
// cocking sound cannot play with the games own sound and must only play once the gun is quiet"): a press is held for
// DRY_WAIT_S; if the game played any gun sound of its own meanwhile (the sounds script's counter, S_GAME_SFX_SEQ) ours stays
// quiet, else the hammer plays. Measured on the simulator: the F2 run dry with spare rounds made its own empty sound on the first
// empty pull only (-26 dBFS), then nothing on eight more [verified-live 2026-11-01, n=1].
namespace {
bool g_pending = false;
float g_press_t = 0.0f, g_press_seq = 0.0f;
const char* g_press_why = "";
bool muted_by_file() {   // a test switch: reframework/data/visceral_re8/dry_click_off present = ours stays quiet
    static float t_check = -10.0f;
    static bool muted = false;
    if (joints::now_s() - t_check > 1.0f) {
        t_check = joints::now_s();
        wchar_t exe[MAX_PATH]{};
        GetModuleFileNameW(nullptr, exe, MAX_PATH);
        muted = std::filesystem::exists(std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "dry_click_off");
    }
    return muted;
}
float game_sfx_seq() { const float v = bridge::view(bridge::S_GAME_SFX_SEQ); return bridge::has(v) ? v : 0.0f; }
void play_click() {
    const char* how = "the hammer";
    if (DRY_GAME_SHOT && game_dry_shot()) how = "the game's own dry shot";
    else if (bridge::lua_has_sfx(bridge::SFX_DRY_FIRE)) { bridge::sfx(bridge::SFX_DRY_FIRE); how = "the sound given job 12"; }
    else if (load()) PlaySoundA(g_wav.data(), nullptr, SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
    static int n = 0;
    if (++n <= 5 || n % 100 == 0) LOGI("%s dry fire: click (%s, #%d): %s", TAG, g_press_why, n, how);
}
} // namespace

void frame() {
    if (g_pending && joints::now_s() - g_press_t >= DRY_WAIT_S) {   // the held press: the game had its moment
        g_pending = false;
        if (game_sfx_seq() != g_press_seq) {
            static int q = 0;
            if (++q <= 10 || q % 100 == 0) LOGI("%s dry fire: the game played its own sound for this press (%s): ours stays quiet (#%d)", TAG, g_press_why, q);
        } else if (!muted_by_file()) play_click();
    }
    if (!bridge::pressed(bridge::S_RTRIG)) return;
    if (!bridge::flag(bridge::S_CAN_USE_HANDS) || bridge::flag(bridge::S_CUTSCENE)) return;
    if (!reload::managed_now()) return;
    const char* why = why_not();
    if (why == nullptr) return;
    // never cut the last click off (Tefa 2026-10-31): a press before it has finished stays quiet
    static auto last = std::chrono::steady_clock::time_point{};
    const auto now = std::chrono::steady_clock::now();
    if (now - last < std::chrono::duration<float>(DRY_CLICK_GAP_S)) return;
    last = now;
    g_pending = true;
    g_press_t = joints::now_s();
    g_press_seq = game_sfx_seq();
    g_press_why = why;
}

} // namespace vn::dryfire
