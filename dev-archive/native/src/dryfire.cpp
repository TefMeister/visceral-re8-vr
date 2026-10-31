// dryfire.cpp -- see dryfire.h.
#include "dryfire.h"
#include "breech.h"
#include "bridge.h"
#include "common.h"
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
    const auto f = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "sfx" / "dry_click.wav";
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
} // namespace

void frame() {
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
    // the game's own empty click when the sounds script has one (job 12, given from its heard list); our wav until then
    if (bridge::lua_has_sfx(bridge::SFX_DRY_FIRE)) bridge::sfx(bridge::SFX_DRY_FIRE);
    else if (load()) PlaySoundA(g_wav.data(), nullptr, SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
    static int n = 0;
    if (++n <= 5 || n % 100 == 0) LOGI("%s dry fire: click (%s, #%d)", TAG, why, n);
}

} // namespace vn::dryfire
