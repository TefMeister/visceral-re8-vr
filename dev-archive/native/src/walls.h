// walls.h -- the hands stop at walls (2026-11-18, Tefa: "see if you can get the hand to collide with walls").
// lua/visceral_re8_walls.lua casts a ray each frame from about each shoulder to where praydog's VR layer puts the hand (the
// same world ray the thrown magazine uses to find the floor, proven on the simulator 2026-11-05) and, when a wall is in the
// way, hands over that wall as a plane (bridge S_WALL_*: a point already the hand's radius off it, and its normal). Here,
// right before the game solves the arm (ik.cpp), the hand's IK target is kept on the player's side of that plane: it slides
// along the wall instead of going through it. Keeping it on the plane (not adding a push) gives the same answer however many
// times the game solves the arm in one frame. A gun in the right hand follows the hand, so it stops too (the Emporium's
// "with a gun in the hand too" switch, in the Lua, can leave guns out). Doors and gates are never walls here: doors.cpp
// pushes them with the hand (the Lua leaves out anything whose name says door or gate).
#pragma once
#include "common.h"

namespace vn::walls {
void on_ik(MO* ik);   // ik.cpp, FIRST: before recoil, the docking and the poses, so they all start from the stopped hand
} // namespace vn::walls
