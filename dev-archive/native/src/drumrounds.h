// drumrounds.h -- the Wolfsbane's rounds made visible while it is loaded by hand (2026-11-06, Opus, home PC).
//
// Tefa, 2026-11-06: "the empty shells must eject visibly when rotating the drum and there is a spent bullet case in the chamber"
// and "bullets must be visible in Ethans right hand when inserting them".
//
// The gun has no loose round of its own: its rounds are joints in the drum, Five_Bullet00-04 (Seven_Bullet00-06 for a bigger
// drum), all under Cylinder (gun survey 2026-10-24). So:
//   carry   while the right hand holds rounds, the round of the chamber that fills next (Five_Bullet[loaded]) is drawn between
//           the right thumb and index tips (world write after the animation); the menu's "round in the hand" sliders move,
//           turn and size it as for the other guns. RT at the cover: it goes home into its chamber and the game counts it.
//   eject   LT turning the drum with a spent case in it: a chamber's round joint falls out of the cover (the Lid joint) and
//           drops away, then goes home. The game's own case throw (app.WeaponCore.ejectCartridge, from cartridgeJoint) is
//           tried as well, with cartridgeJoint pointed at the cover; the log says whether it did anything.
// How the game hides an empty chamber is NOT known yet [hypothesis: a mesh part per chamber, or the joint scaled to 0]. Both are
// handled: a joint scaled to ~0 is drawn at its own size while we use it, and the mesh part that the game switches on when a
// chamber fills is learned live (logged as "drumrounds: chamber N is part P") and switched on while we use that chamber;
// before it is learned, the gun's own rounds-parts list (switchVanishEmptyPartsDisp), when it has one part per chamber, is
// used as a first guess. Everything we changed is put back when we let go of it.
#pragma once
#include "common.h"

namespace vn::drumrounds {

void point(bool carrying);   // gate.cpp late_point, after the drum's turn: carrying = the right hand holds rounds (HELD)
void inserted();             // gate.cpp, a round went in from the right hand: the carried one is home
void eject(float delay);     // gate.cpp: a spent case comes out of the chamber at the cover after delay s (the cover opening, the
                             // drum's turn); that chamber then looks EMPTY (its round joint hidden) until a round goes into it
void reset(const char* why); // gate.cpp, the gun changed / the hold ended: every joint home, every part as the game had it
void tune(float yaw, float pitch, float roll);   // lid_swing.json "round_ypr" (breech.cpp): the round's turn in the hand

} // namespace vn::drumrounds
