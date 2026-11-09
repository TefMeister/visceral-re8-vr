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
void publish_zone();  // once a frame: this gun's kept grip spot as the FRONT GRIP zone (zones.h GRIP) for the menu and the grip script
// 2026-11-09 (b102): how far the left hand's glide onto / off a part has come, on the same curve the hand moves by
// (0 = just started, 1 = arrived); easing() = a glide is under way. dockpose.cpp moves Hand Poser's numbers along it
bool easing();
float progress();
int glide_id();       // +1 at each new glide (a change of who places the hand)
} // namespace vn::smooth
