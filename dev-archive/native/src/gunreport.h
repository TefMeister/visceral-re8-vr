// gunreport.h -- the gun's place in the hand, measured and written down every few seconds (2026-10-29, Fable).
//
// Tefa, asked what "the guns are wrong again" looks like: "the picture is at the right height; the gun only: it's too low,
// it's like my right hand is just above the gun and when I rotate my wrist the gun swings like a pendulum instead of a
// wrist and hand rotating naturally". A pendulum has an arm: some centimetres between the point the wrist turns about
// and the gun. On a good launch that arm is zero. Nothing in the settings differs between a good and a bad launch
// (checked 2026-10-25), so the difference is in the running game, and nobody has measured it yet. This does:
//   - the right hand's IK target (where praydog's script asks the hand to be: the controller + his offsets),
//   - the hand joint itself (where the game's arm actually put it),
//   - the gun's root, and where it sits IN THE HAND'S OWN FRAME (the number that should never change),
//   - the arm's reach: shoulder to target against the arm's length (a target out of reach leaves the hand short),
//   - the game's flags that change the placement (aiming, hands usable, reloading, the left hand docked).
// One line every GUNREPORT_PERIOD_S, and at once when the gun moves in the hand by more than GUNREPORT_CHANGE_M. To the
// REFramework log and to its own dated file (reframework/data/visceral_re8/gunreports/), because the REFramework log is
// overwritten at the next launch and the bad launch is the one nobody kept.
#pragma once

namespace vn::gunreport {

void frame();   // once a frame, after player::refresh() (plugin.cpp)

} // namespace vn::gunreport
