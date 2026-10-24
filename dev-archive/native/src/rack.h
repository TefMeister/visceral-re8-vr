// rack.h -- the slide / bolt / charging-handle rack and the pump for Village, with the left hand ON the gun
// (2026-10-18, moved over from the RE7 RELOADED mod; the gesture is Visceral RE2's, Tefa b165/b166):
//   slide / bolt: when the gun is empty or a rack is needed (or "hold this pose" is on): left grip with the left hand on
//                 the gun line (over the gun hand or ahead of it) puts the hand on; LT = the pull is live; move the left
//                 controller back along the gun; once fully back, letting go of the left grip sends it forward.
//   pump:         left grip + LT with the left hand on the barrel line arms one cycle; pull back, let go of LT.
// The left hand is held where it took hold, relative to the gun hand, and slides back with the pull: rack.cpp rewrites
// the left IK target right before each left-arm solve (ik.cpp). The slide joint is only moved when "_01" exists on the
// gun (Village's gun parts are not known yet; the first hold logs them).
#pragma once
#include "common.h"

namespace vn::rack {

void frame();            // UpdateBehavior pre: the gesture, the timers
void late_point();       // LateUpdateBehavior post: write the slide joint
void render_point();     // PrepareRendering post: write it again
void begin_render_point(); // BeginRendering pre: and once more (the F2 bolt did not move with the first two, 2026-10-19)
void on_ik(MO* ik);      // ik.cpp: the left hand is about to be solved: hold it on the gun while docked

void need(const char* why);   // reload.cpp: a rack / pump is required before the gun fires
bool needed();
bool active();                // the left hand is on the slide / bolt / pump
bool pump_gun();
float left_gun_closeness();   // 0 = the left controller far from the gun, 1 = in the grab zone (fingers.cpp eases on it)              // the gun in hand is a pump gun: its two-handed grip IS the pump (handstate.cpp vetoes the grip script)
bool left_near_gun();         // the left controller in a grab area: the slide / pump / bolt part, or the line along the gun (fingers.cpp)
bool on_pump();
float travel();               // 0 = rest, 1 = fully back
void* slide_joint();          // this frame's slide / pump / bolt joint (ghosthand.cpp), or nullptr
const char* part_name();      // "slide" | "pump" | "bolt"

} // namespace vn::rack
