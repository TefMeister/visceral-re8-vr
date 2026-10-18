// ik.h -- the one hook on app.AnimIK2Bone.calc (the game solving an arm toward its IK target). praydog's VR layer sets both
// hand targets and calls calc itself; the game calls it again in its own motion pass. Right before each solve of a
// player hand: recoil.cpp adds the kick, then rack.cpp puts the left hand on the slide while it is docked there.
#pragma once

namespace vn::ik {
void install();   // first game frame
} // namespace vn::ik
