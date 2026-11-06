// shellclip.h -- the game's own finger movements, played on the docked hands at the moment our code does the thing
// (2026-11-02 the W870's shell-in on the left hand, Opus; 2026-11-04 every gun, both hands, named events, Fable).
//
// Tefa, 2026-11-02: "can you just try one gun in re8 with opus, to see if you can put the games original finger movements
// into inserting a shell into w870 shotgun, so that in the activation zone, hand can still be moved, but the finger
// animation of a shell being insetred plays when the shell goes in"; and the wider ask the same day: "default hand
// animations, just the hand and fingers, so wrists are not locked and hands can still be naturally moved in vr ... use
// these hand grip poses when gripping weapons in VR".
//
// The clips are cut from the finger takes by tools/make_finger_book.py into reframework/data/visceral_re8/clips/
// <gun>_<event>.csv (the game's animation data, so they stay on the PC, never on GitHub). Events: round_in (a round pushed
// in: the left hand on the shotguns and the Rocket Pistol, the RIGHT hand on the revolvers, as the game does it), mag_out
// (the magazine grasped and pulled), mag_in (the new one pushed home); rack and reload are written but not played yet.
// A clip's header names the joints it moves (L_IndexF1 ... R_Thumb3), so a clip drives one hand or both; a new clip on a
// hand replaces the one playing there. Blended in from the pose the hand had, played at its own speed, blended back out
// to whatever the game and the other finger code want. Only finger joints' local rotations are written: where the hand
// IS stays the controller's (reload.cpp / the IK). Written last at both render points, so it wins over fingers.cpp,
// righthand.cpp and Hand Poser while it plays.
// Test without a headset: write "<gun> [event]" (e.g. "ri3046 mag_out") into reframework/data/visceral_re8/clips/play.txt;
// it plays once on whatever is in hand (the file is emptied). Log lines "[visceral-re8] shellclip: ...".
#pragma once
#include <string>
#include <vector>

namespace vn::shellclip {

// 2026-11-06 (Tefa: "when adding bullets, both hands animate at the same time, adding bullets and rotating the drum when pressing
// RT"): the Wolfsbane's round_in clip moves BOTH hands (the game's 2512 cycle: right thumb pushes the round, left thumb turns the
// drum). A play can now be limited to one hand: RT at the cover plays its right half, LT (the drum's turn) its left half.
constexpr int LEFT = 1, RIGHT = 2, BOTH = 3;
void play(const std::string& gun_id, const char* event = "round_in", int hands = BOTH);   // gun_id like "ri3021_Inventory" or "ri3021"
// 2026-11-06 (Tefa: "right thumb needs to flick the bullet guard open"): a movement of our own, not the game's: the named joints
// turn about their own local axis by deg and back (a half sine) over sec, on top of whatever pose they have; written last, as
// the clips are. right = it belongs to the right hand (playing_right() while it runs)
void pulse(const std::vector<std::wstring>& joints, float ax, float ay, float az, float deg, float sec, bool right);
void frame();                           // UpdateBehavior pre: the test file
void render_point();                    // PrepareRendering post, after every other finger writer
void begin_render();                    // BeginRendering pre, after every other finger writer
bool playing();                         // any hand
bool playing_left();                    // fingers.cpp / righthand.cpp stand aside for the left hand meanwhile
bool playing_right();

} // namespace vn::shellclip
