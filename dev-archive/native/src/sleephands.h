// sleephands.h -- a controller gone to sleep lowers its hand to the player's side (2026-11-09, Tefa in the headset: "when the
// controllers go inactive, is there a way to not make Ethans hands jump up right in front of my face", then "make the hands go
// down on the sides when controllers go to sleep").
// A sleeping controller stops being tracked and its pose freezes exactly (b087's log: "controller turn 0.0000 deg a frame" for
// whole 10 s spells while the controllers lay down); a hand held, or even resting tracked, always moves by a hair. So: a
// controller whose room position and turn have not changed at all for SLEEP_FRAMES frames is asleep, and its hand's IK target is
// eased down to beside the hip (from the headset: SLEEP_DOWN_M down, SLEEP_SIDE_M out to its side, SLEEP_FWD_M forward, the
// headset's turn about up only), keeping the hand's turn. The first change wakes it: the hand eases back to the controller.
// Runs LAST in the IK chain (ik.cpp), on top of everything else. First cut, not worn (2026-11-09).
#pragma once
#include "common.h"

namespace vn::sleephands {

void frame();          // UpdateBehavior pre (after the bridge Lua wrote this frame's controller poses): asleep or not, the ease
void on_ik(MO* ik);    // ik.cpp, LAST: a sleeping hand's target moved to its rest beside the hip

} // namespace vn::sleephands
