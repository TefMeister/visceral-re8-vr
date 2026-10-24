// nodock.h -- the game's own left-hand dock is switched off while the left grip is up (2026-10-25, Fable).
//
// praydog's RE8VR::update_hand_ik docks the left hand whenever the controller comes within 10 cm of the animation's left
// wrist (relative to the right hand), button or not, and turns the gun toward it. Tefa's rule since 2026-10-24: the hand
// goes onto the gun only with LG held. Every fix downstream (the grip script's undo, smooth.cpp's put-back) ran a solve
// late and the hand or the gun still flicked (live watch 01:06: the dock switched on and off four times in four seconds).
// praydog finds that wrist by asking the player's Motion for the joint index of the left hand IK's joint hash
// (via.motion.Motion.getJointIndexByNameHash). While LG is up that call, for that hash, on the player's motion, answers 0
// (the root joint, at the feet): the dock's socket sits a metre from the hand and the dock never fires. With LG held the
// real answer is given, so the rack, the grip script and the magazine paths see what they always saw. The plugin's own
// reads of that joint (player::motion_joint_hash, the kept holds) are marked and never faked.
#pragma once

namespace vn::nodock {

void install();     // once: hooks via.motion.Motion.getJointIndexByNameHash
void frame();       // UpdateBehavior pre: decides whether the fake is on this frame
bool on();          // the fake is on this frame

extern thread_local bool t_self_read;   // set by the plugin around its own joint-index reads

} // namespace vn::nodock
