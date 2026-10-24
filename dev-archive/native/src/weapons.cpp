// weapons.cpp -- see weapons.h
#include "weapons.h"
#include "player.h"

#include <windows.h>

#include <cstdio>
#include <filesystem>
#include <map>

namespace vn::weapons {

namespace {
using R = Reload;
using S = Shape;
using B = Breech;
const Weapon WEAPONS[] = {
    // id                  name                          reload    shape       rack   pump
    {"ri3040_Inventory", "M1911",                      R::MAG,   S::PISTOL,  true,  false},
    {"ri3046_Inventory", "LEMI",                       R::MAG,   S::PISTOL,  true,  false},
    {"ri3047_Inventory", "V61 Custom",                 R::MAG,   S::PISTOL,  true,  false},
    {"ri3050_Inventory", "S.T.A.K.E",                  R::MAG,   S::PISTOL,  true,  false},
    // Rocket Pistol: no Magazine and no Slide joint, but a Lid opened by a Lever and two rockets Bullet00 / 01 (gun survey
    // 2026-10-24), so the game's own reload stays on until its reload has been watched
    {"ri3115_Inventory", "Rocket Pistol",              R::NONE,  S::PISTOL,  false, false},
    {"ri3122_Inventory", "Samurai Edge - AW Model-01", R::MAG,   S::PISTOL,  true,  false},
    {"ri3124_Inventory", "USM-AI",                     R::MAG,   S::PISTOL,  true,  false},
    {"ri3135_Inventory", "LEMI - Shadows of Rose",     R::MAG,   S::PISTOL,  true,  false},
    {"ri3081_Inventory", "LEMI - Mercenaries",         R::MAG,   S::PISTOL,  true,  false},
    {"ri3082_Inventory", "M1911 - Mercenaries",        R::MAG,   S::PISTOL,  true,  false},
    {"ri3083_Inventory", "V61 Custom - Mercenaries",   R::MAG,   S::PISTOL,  true,  false},
    {"ri3130_Inventory", "USM-AI - Mercenaries",       R::MAG,   S::PISTOL,  true,  false},
    {"ri3042_Inventory", "F2 Rifle",                   R::MAG,   S::LONG,    true,  false, true},
    {"ri3087_Inventory", "F2 Rifle - Mercenaries",     R::MAG,   S::LONG,    true,  false, true},
    {"ri3049_Inventory", "WCX",                        R::MAG,   S::LONG,    true,  false},
    {"ri3125_Inventory", "Dragoon",                    R::MAG,   S::LONG,    true,  false},
    {"ri3129_Inventory", "Dragoon - Mercenaries",      R::MAG,   S::LONG,    true,  false},
    {"ri3048_Inventory", "SYG-12",                     R::MAG,   S::LONG,    true,  false},
    {"ri3086_Inventory", "SYG-12 - Mercenaries",       R::MAG,   S::LONG,    true,  false},
    {"ri3021_Inventory", "W870 TAC",                   R::ROUND, S::LONG,    false, true},
    {"ri3085_Inventory", "W870 TAC - Mercenaries",     R::ROUND, S::LONG,    false, true},
    {"ri3036_Inventory", "M1897",                      R::ROUND, S::LONG,    false, true},
    {"ri3084_Inventory", "M1897 - Mercenaries",        R::ROUND, S::LONG,    false, true},
    {"ri3147_Inventory", "M1897 - Shadows of Rose",    R::ROUND, S::LONG,    false, true},
    {"ri3023_Inventory", "GM 79",                      R::ROUND, S::LONG,    false, false, false, B::BREAK},
    {"ri3008_Inventory", "M1851 Wolfsbane",            R::ROUND, S::PISTOL,  false, false, false, B::CYLINDER},
    {"ri3116_Inventory", "Handcannon PZ",              R::ROUND, S::PISTOL,  false, false, false, B::CYLINDER},   // a revolver: Cylinder with Bullet00-04 (survey 2026-10-24)
    {"ri3022_Inventory", "Knife (melee)",              R::NONE,  S::PISTOL,  false, false},
    {"ri3044_Inventory", "Knife (melee, 2)",           R::NONE,  S::PISTOL,  false, false},
};

constexpr int WATCH_EVERY_FRAMES = 120;
std::map<std::string, std::string> g_seen;

void save() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto dir = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8";
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    FILE* f = nullptr;
    if (_wfopen_s(&f, (dir / "weapon_ids.json").c_str(), L"wb") != 0 || f == nullptr) return;
    std::fprintf(f, "{\n");
    size_t i = 0;
    for (auto& [k, v] : g_seen) std::fprintf(f, "    \"%s\": \"%s\"%s\n", k.c_str(), v.c_str(), ++i < g_seen.size() ? "," : "");
    std::fprintf(f, "}\n");
    std::fclose(f);
}

void note(const std::string& key, const std::string& what) {
    if (key.empty() || g_seen.count(key)) return;
    g_seen[key] = what;
    LOGI("%s weapon id seen: %s (%s)", TAG, key.c_str(), what.c_str());
    save();
}
} // namespace

std::string canonical(const std::string& raw) {
    if (raw.empty()) return raw;
    for (const auto& w : WEAPONS) if (raw == w.id) return raw;
    const std::string inv = raw + "_Inventory";
    for (const auto& w : WEAPONS) if (inv == w.id) return inv;
    return raw;
}

const Weapon* find(const std::string& raw) {
    const std::string id = canonical(raw);
    for (const auto& w : WEAPONS) if (id == w.id) return &w;
    return nullptr;
}

const char* name(const std::string& raw) {
    const Weapon* w = find(raw);
    return w != nullptr ? w->name : "not in our list";
}

void watch() {
    static int frame = 0;
    if (++frame % WATCH_EVERY_FRAMES != 0) return;
    const auto& s = player::now();
    if (!s.weapon_id.empty()) note(s.weapon_id, find(s.weapon_id) ? std::string("listed: ") + name(s.weapon_id) : "NEW (held)");
}

} // namespace vn::weapons
