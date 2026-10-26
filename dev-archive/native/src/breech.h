// breech.h -- the guns that open to load (2026-10-19, Tefa: "yes for village"): the revolvers' cylinder (M1851
// Wolfsbane, Handcannon PZ) and the GM 79's barrel (break action). Before, each was loaded like a pump shotgun: one round
// per grab from the ammo spot, straight in.
//   open    right B, or a flick of the gun hand: the revolver ROLLED sharply to the left (the cylinder swings out to
//           the left), the GM 79's muzzle snapped DOWN (the barrel drops open)
//   load    rounds from the ammo spot go in only while it is open (reload.cpp asks loading_allowed())
//   close   right B again, or the opposite flick (rolled right / muzzle snapped up)
//   fire    refused while it is open
// The flick is read from the right controller's own turn between frames (room space), around its own axes, so it works
// whichever way the gun points. The cylinder / barrel is not drawn moving yet: Village's joint names for them are not
// known (the joint log on the first hold prints them).
#pragma once
#include "common.h"

namespace vn::breech {

void frame();               // UpdateBehavior pre, after reload::frame(): the flick, right B, the weapon change
bool here();                // the gun in hand opens to load
bool is_open();
bool loading_allowed();     // not a breech gun, or it is open
bool blocks_fire();         // a breech gun that is open
// 2026-10-27 (Tefa): the revolver's drum opens only with LG at the drum (pairs.cpp's DRUM dock), never with right B or a
// flick; while the hand holds the drum each LT puts a round in, and the LT after it is full closes it (a flick closes it too).
// The GM 79: LG + LT at the insert point takes out what is in the barrel, a live grenade (back to the carried ammo) or the
// spent case; a fresh grenade goes in only once the spent case is out; LT with the left hand on the front grip opens / closes it.
void drum_taken();         // LG at the drum: it opens
void drum_lt();            // LT with the hand on the drum: one round in, or closed when full
void insert_lt();          // LT with the hand at the GM 79's insert point: the round or the spent case comes out
bool spent();              // the GM 79 holds a spent case (fired, not taken out yet)

} // namespace vn::breech
