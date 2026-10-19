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

} // namespace vn::breech
