// rec.h -- rebuild 2 (2026-11-26, RE8-091): the recorders. Lanes PROTOCOL sections 18 and 20: every VR mod in
// early development has the jitter recorder wired in, and a mod with hand gestures has Ghost Hand.
//
// Three files per headset session, written only while the headset and the controllers are in use (the bridge says
// so); a flat run writes nothing:
//   Camera Jitter BeG0nE   begone/jitterlog.h: the headset as the loader reports it, the camera as the game has it,
//                          one tick per picture, the controllers. Lanes' rider files it.
//   Ghost Hand BeG0nE      begone/ghosthand.h: the controllers, the hands the game draws, the feet, knees and hip as
//                          "parts", all in the HEAD's own space (so a walk does not smear them). The rider files it.
//   the walk file          reframework/data/visceral_re8/walkrec/walk-<date>-<time>.csv: one line per picture for
//                          the legs' fault (Tefa, 2026-11-26: "legs glitchy when walking", the step starting over
//                          about four times a second): the feet and knees in the PLAYER's own space, the walk
//                          motion's number and frame, the stick as it was handed to the game, the flags, the lean
//                          fix's numbers. tools/walkread.py reads it and counts.
//
// Where: PrepareRendering post, after the joint writer: the body as it is drawn. It reads; it writes no joint, hooks
// nothing, asks the game for nothing. It runs even when off.txt says `frame` (so the bare base can be measured).
// Its switch in off.txt: recorders.
// The headset's pose is the loader's copy (the plugin API hands a plugin no pose of its own): the jitter report's
// "pose age" is from that copy, not from the runtime's read.
#pragma once

namespace vr8::rec {

void pose();        // PrepareRendering post, once per picture, after ready::render_tick() and leanfix::pose()
void shutdown();    // closes the files (also done when the headset goes out of use)

} // namespace vr8::rec
