// handstate.h -- what each hand is doing right now, named, for the hand poses (Tefa 2026-10-18: "function enough for me
// to start doing hand poses for them - hands on the weapon grip, slide and left hand on it's own").
//   left:  free | grip (praydog docked it on the gun) | slide | pump | magazine | round
//   right: bare | weapon
// Written to reframework/data/visceral_re8/hand_state.json whenever it changes ({"left": .., "right": .., "weapon": ..}),
// shown in the bridge's REFramework menu ("Visceral RE8 reload"), and used to keep the game's block pose out of a reload
// (the bridge sets __visceral_reload_busy, which our re8_vr.lua honours). Moved over from the RE7 RELOADED mod, 2026-10-18.
#pragma once

namespace vn::handstate {

enum Left : int { FREE = 0, GRIP = 1, SLIDE = 2, PUMP = 3, MAGAZINE = 4, ROUND = 5 };

void frame();   // UpdateBehavior pre, after the features
const char* left_name(int code);

} // namespace vn::handstate
