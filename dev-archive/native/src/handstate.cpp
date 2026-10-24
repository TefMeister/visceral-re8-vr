// handstate.cpp -- see handstate.h
#include "handstate.h"
#include "bridge.h"
#include "common.h"
#include "player.h"
#include "rack.h"
#include "reload.h"

#include <windows.h>

#include <cstdio>
#include <filesystem>
#include <string>

namespace vn::handstate {

namespace {
int g_left = -1;
bool g_right = false;
std::string g_weapon = "?";

void save() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto dir = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8";
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    FILE* f = nullptr;
    if (_wfopen_s(&f, (dir / "hand_state.json").c_str(), L"wb") != 0 || f == nullptr) return;
    std::fprintf(f, "{\n    \"left\": \"%s\",\n    \"right\": \"%s\",\n    \"weapon\": \"%s\"\n}\n", left_name(g_left), g_right ? "weapon" : "bare",
                 g_weapon.c_str());
    std::fclose(f);
}
} // namespace

const char* left_name(int code) {
    switch (code) {
    case GRIP: return "grip";       case SLIDE: return "slide";   case PUMP: return "pump";
    case MAGAZINE: return "magazine"; case ROUND: return "round"; default: return "free";
    }
}

void frame() {
    int left = FREE;
    if (rack::active()) left = rack::on_pump() ? PUMP : SLIDE;
    else if (reload::mag_in_hand()) left = MAGAZINE;
    else if (reload::round_in_hand()) left = ROUND;
    else if (bridge::flag(bridge::S_GRIPPING_WEAPON)) left = GRIP;
    const auto& s = player::now();
    const bool right = s.weapon != nullptr;
    bridge::put(bridge::S_HAND_STATE, (float)left);
    // the held gun's number for the menu's per-gun settings (ri3046 -> 3046)
    int num = 0;
    for (char c : s.weapon_id) { if (c >= '0' && c <= '9') num = num * 10 + (c - '0'); else if (num > 0) break; }
    bridge::put(bridge::S_WEAPON_NUM, right ? (float)num : 0.0f);
    bridge::put(bridge::S_RELOAD_BUSY, (left == SLIDE || left == PUMP || left == MAGAZINE || left == ROUND || reload::session_active()) ? 1.0f : 0.0f);
    if (left == g_left && right == g_right && s.weapon_id == g_weapon) return;
    if (left != g_left) LOGI("%s hands: left %s -> %s", TAG, left_name(g_left), left_name(left));
    g_left = left;
    g_right = right;
    g_weapon = s.weapon_id;
    save();
}

} // namespace vn::handstate
