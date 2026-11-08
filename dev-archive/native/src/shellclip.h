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
// tag: who started it, for part() below ("drum" = gate.cpp's LT turn); nullptr = nobody in particular
void play(const std::string& gun_id, const char* event = "round_in", int hands = BOTH, const char* tag = nullptr);   // gun_id like "ri3021_Inventory" or "ri3021"
// 2026-11-08 (Tefa: "it's only half of the solution if the drum doesn't travel frame by frame as well"): a gun PART that moves
// with a clip (the Wolfsbane's drum with round_in) takes its progress from the clip's own frames, not from a clock of its own:
// 0 at the clip's first frame, 1 at its last, straight along the edited time unless the window keyed it ("parts":{"drum":u} on
// a nudge key: then it runs through those keyed values, with 0 / 1 at the ends where those frames carry no key). So a held
// frame holds the part, and SLOWER / ADD ONE HERE retime it with the hand. declare_part() tells the window the clip has that
// part (a slider appears); part() = the progress of the play of that clip started with `tag` or held by the window, false when
// none plays (the caller goes back to its own clock).
void declare_part(const std::string& gun_id, const char* event, const char* part);
bool part(const std::string& gun_id, const char* event, const char* part, const char* tag, float& u);
// 2026-11-06 (Tefa: "right thumb needs to flick the bullet guard open"): a movement of our own, not the game's: the named joints
// turn about their own local axis by deg and back (a half sine) over sec, on top of whatever pose they have; written last, as
// the clips are. right = it belongs to the right hand (playing_right() while it runs)
void pulse(const std::vector<std::wstring>& joints, float ax, float ay, float az, float deg, float sec, bool right);
// 2026-11-06 (Tefa: "might still be able to use the game's animations, if i can change the docking pose and then you somehow work
// your magic to fill the gaps from my hand tuned pose to smoothly travel to the game's original animation"): RELATIVE mode plays
// a clip as a CHANGE on top of the pose the hand had (Tefa's tuned pose): each joint = found * (clip's first frame)^-1 * clip(t),
// so the hand starts exactly in the tuned pose and moves the way the game's fingers move. Switched on by the file
// reframework/data/visceral_re8/clips/relative.txt existing (checked 4 times a second; delete it for the plain blend).
// 2026-11-07 (Tefa: "fine tune that original hand movement and placement frame by frame"): the Animation & Timing window
// (animation-timing-vr) edits a clip without touching the game's CSV: clips/<gun>_<event>.edit.json holds frame ops (remove a
// frame, hold one longer, retime a range) and nudges keyed by the CSV row (a turn per finger joint, a move of the WHOLE hand on
// the gun: x y z cm, rx ry rz deg in the gun's axes), interpolated between keyed frames. clips/scrub.json holds a clip on one
// edited frame (or plays it once); clips/clips_state.json (twice a second) tells the window the gun's clips and what plays.
// The whole-hand move of the clip playing on a hand right now (metres, degrees, already scaled by the blend); false = none.
// dockpose.cpp (the last writer on the IK target) adds it on top of whoever placed the hand.
bool hand_nudge(bool left, float out[6]);
void frame();                           // UpdateBehavior pre: the test file, the relative switch, scrub.json, clips_state.json
void render_point();                    // PrepareRendering post, after every other finger writer
void begin_render();                    // BeginRendering pre, after every other finger writer
bool playing();                         // any hand
bool playing_left();                    // fingers.cpp / righthand.cpp stand aside for the left hand meanwhile
bool playing_right();

} // namespace vn::shellclip
