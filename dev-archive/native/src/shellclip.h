// shellclip.h -- the game's own finger movement for a round going in, played on the hand that put it in (2026-11-02, Opus).
//
// Tefa, 2026-11-02: "can you just try one gun in re8 with opus, to see if you can put the games original finger movements
// into inserting a shell into w870 shotgun, so that in the activation zone, hand can still be moved, but the finger
// animation of a shell being insetred plays when the shell goes in".
//
// The clip is one cycle of the game's own shell-in motion (2512 on the W870), cut from a finger take by
// tools/make_finger_clip.py into reframework/data/visceral_re8/clips/<gun>_round_in.csv (the game's animation data, so it
// stays on the PC, never on GitHub). When reload.cpp puts a round in, the LEFT hand's 15 finger joints play it: blended in
// from the pose they had, the clip at its own speed, blended back out to whatever the game and the other finger code want.
// Only the finger joints' local rotations are written: where the hand is stays the controller's (reload.cpp / the IK).
// Written last at both render points, so it wins over fingers.cpp, righthand.cpp and Hand Poser while it plays.
// Test without a headset: write the gun's short id (e.g. "ri3021") into reframework/data/visceral_re8/clips/play.txt;
// the clip plays once on whatever is in hand (the file is emptied). Log lines "[visceral-re8] shellclip: ...".
#pragma once
#include <string>

namespace vn::shellclip {

void play(const std::string& gun_id);   // reload.cpp: a round went in (gun_id like "ri3021_Inventory" or "ri3021")
void frame();                           // UpdateBehavior pre: the test file
void render_point();                    // PrepareRendering post, after every other finger writer
void begin_render();                    // BeginRendering pre, after every other finger writer
bool playing();                         // fingers.cpp / righthand.cpp stand aside meanwhile

} // namespace vn::shellclip
