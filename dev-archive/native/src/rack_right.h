// rack_right.h -- the RIGHT hand works the bolt while the left hand holds the gun by its front (2026-11-01).
// Tefa: "with the rifle, holding it with LG on the fron part then holding LT makes it possible to press RG and the right
// hand goes on the bolt to rack it. left can still do it too".
//
// The gun hangs off the right hand in the game, so while the right hand is on the bolt the gun is carried by the LEFT
// controller: at the take, the gun, the right hand's target and the left hand's target are each kept in the left
// controller's frame.
// 2026-11-01, after the first wear (Tefa: "really cool! it works ... throws the gun a little and left hand doesn't stay on like
// solidly holding on to the gun ... can the LT press on the front of the rifle make it freeze in place and bolt racking can be
// done at any time with RG"): LT held with the left hand on the front LOCKS the rifle in the left hand (taken then, while the
// hands are calm; the right hand rides the grip), and RG works the bolt any time while it is locked. LT let go = the gun
// handed back to the right hand. While RG is held:
//   - the gun's own transform is written every frame where the left controller now carries it (late update + before
//     rendering, after the arm solves), so it stays put in the left hand while the right hand leaves the grip;
//   - the left hand is drawn where it was on the front, riding the left controller;
//   - the right hand glides from the grip onto the bolt joint and rides it (back, forward, the turn);
//   - the bolt cycle itself is rack.cpp's (LT lifts it, pull back, push home, the clicks), read from the right controller.
// RG let go: the right hand glides back to the grip, the gun's own transform is put back as it was, and the gun is handed
// back to the right controller with a short ease. Every take logs what it read, and once a second while the gun is held by
// the left hand, how far the drawn gun is from where it was put (the proof the game did not take it back).
#pragma once
#include "common.h"

namespace vn::rack_right {

void frame(bool play, bool lg, bool lt);   // rack.cpp's frame, before its own take: the RG gesture and the phases
void abort(const char* why);               // rack.cpp: no gun / no headset: everything put back at once
void on_ik(MO* ik);                         // ik.cpp, LAST: both hands' targets while the right hand has the bolt
void late_point();                          // LateUpdateBehavior post: the gun where the left hand carries it
void render_point();                        // PrepareRendering post: again, after the grip script's last solve
void begin_render_point();                  // BeginRendering pre: and once more, after the arm solves
bool active();                              // the right hand is on (or gliding to / from) the bolt: no shot
bool locked();                              // the rifle is held by the left hand (LT on the front)

} // namespace vn::rack_right
