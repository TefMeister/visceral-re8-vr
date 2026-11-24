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
// 2026-11-24 (b161, Tefa: "i really need hand freeze to work on the mag too to freeze it ... so hand freeze just freezes the hand on
// the part, same with sliders, pump handles and other moving weapon parts"): Hand Freeze holds this hand (or Window View's
// controller mode holds the game's hands). side 0 left, 1 right. reload.cpp (the magazine on the grip) and rack.cpp (slide,
// pump) keep their part where it is meanwhile.
bool held_still(int side);

} // namespace vn::sleephands
