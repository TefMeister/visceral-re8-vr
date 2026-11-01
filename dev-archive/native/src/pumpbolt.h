// pumpbolt.h -- the M1897's bolt (the cover on the receiver's right side) slides with the pump (2026-11-01, Tefa: "animate the
// shotgun shell guard on the right hand side of the weapon to open with the pump handle pull, so it moves just as much as the
// handle does"). rack.cpp moves the pump joint (Reload_Slider) with the hand; the gun's "Bolt" joint got nothing, so it stayed
// shut. Now, after the pump is written, the bolt is given the pump's own offset from rest, every frame.
#pragma once
#include "common.h"

namespace vn::pumpbolt {

void point();   // LateUpdateBehavior post, PrepareRendering post, BeginRendering pre: after rack.cpp's pump writes

} // namespace vn::pumpbolt
