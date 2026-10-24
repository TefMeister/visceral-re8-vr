// smooth.h -- the left hand eased onto and off the gun (2026-10-24, Tefa: "smooth docking to and from the
// slide/handle/bolt and hopefully the same smoothness can be applied to docking the left hand on the weapon").
// Whoever places the left hand (praydog's two-handed grip, rack.cpp on the slide / pump / bolt, or nobody: the
// controller), the moment that changes the hand would jump. So the last thing before each left-arm solve (ik.cpp, after
// every other writer) is this: when the owner changes, the gap between where the hand was drawn and where it is now
// asked to be is kept, in the gun hand's frame, and shrunk to nothing over SMOOTH_DOCK_SEC.
// Menu "Visceral RE8 reload" -> Experiments -> "no smoothing" turns it off live.
#pragma once
#include "common.h"

namespace vn::smooth {
void on_ik(MO* ik);   // ik.cpp: the left arm is about to be solved, after recoil, reload and rack have written
} // namespace vn::smooth
