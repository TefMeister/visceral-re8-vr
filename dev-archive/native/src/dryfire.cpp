// dryfire.cpp -- see dryfire.h.
#include "dryfire.h"
#include "breech.h"
#include "bridge.h"
#include "common.h"
#include "player.h"
#include "rack.h"
#include "reload.h"

#include <windows.h>
#include <mmsystem.h>

#include <filesystem>
#include <fstream>
#include <iterator>
#include <vector>

namespace vn::dryfire {
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
    if (why == nullptr || !load()) return;
    PlaySoundA(g_wav.data(), nullptr, SND_MEMORY | SND_ASYNC | SND_NODEFAULT);   // a new press restarts it: never a missed click
    static int n = 0;
    if (++n <= 5 || n % 100 == 0) LOGI("%s dry fire: click (%s, #%d)", TAG, why, n);
}

} // namespace vn::dryfire
