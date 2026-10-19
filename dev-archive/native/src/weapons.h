// weapons.h -- every Village weapon we know, by the id the game uses (the weapon owner's name, e.g. "ri3046", written
// "ri3046_Inventory" in Andyalpa's files; canonical() turns one into the other), with how it reloads by hand
// (2026-10-18, the reload moved over from Visceral RE7).
//
// The ids and names are Andyalpa's (re8_vr_recoil.lua WEAPON_CATALOG + the two melee ids). How each gun reloads is
// ours, from what the guns are (magazine / single shells / break action / revolver). Village's gun parts (which joint
// is the magazine, which the slide) are not known yet: the first time a gun is held its joints are logged, and the
// magazine / slide visuals only run when the named joint exists. The reload itself does not need them: where the
// magazine or shell goes in is measured from the gun hand in the room (the grip for pistols, ahead along the barrel for
// long guns), and the left hand's place on the slide / pump is taken where it grabbed.
// Weapon ids the game shows that are not below are written to reframework/data/visceral_re8/weapon_ids.json.
#pragma once
#include "common.h"

#include <string>

namespace vn::weapons {

enum class Reload {
    NONE,     // melee, or not handled: the game's own reload stays on
    MAG,      // a magazine: right B drops it, the left-hip ammo spot gives a new one
    ROUND,    // single shells / rounds / grenades: each grab from the ammo spot is one
};
enum class Shape { PISTOL, LONG };
enum class Breech { NONE, CYLINDER, BREAK };   // 2026-10-19: opens to load (breech.cpp): a revolver's cylinder, a break-action barrel   // where the magazine / shell goes in: at the gun hand, or ahead of it along the barrel

struct Weapon {
    const char* id;          // canonical: "ri3046_Inventory"
    const char* name;
    Reload reload;
    Shape shape;
    bool rack;               // a magazine into an empty gun needs a slide / bolt / charging-handle rack
    bool pump;               // pump shotgun: shells into an empty gun need a pump
    bool bolt = false;       // bolt action: pulled back and pushed forward by hand; it stays where it is let go (Tefa 2026-10-19)
    Breech breech = Breech::NONE;
};

std::string canonical(const std::string& raw);   // "ri3046" -> "ri3046_Inventory" when that is in the list
const Weapon* find(const std::string& raw_or_canonical);
const char* name(const std::string& raw_or_canonical);
void watch();                // every ~2 s: log and save weapon ids not in the list (game thread)

} // namespace vn::weapons
