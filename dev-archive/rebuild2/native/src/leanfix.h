// leanfix.h -- rebuild 2 (2026-11-26, RE8-092): the body no longer comes forward into the view when a run stops.
//
// Measures where leanrec measures (PrepareRendering post: the body as it is drawn), works the ask out with
// leanmath.h, and puts it in the bridge array (S_LEAN). The script's body placing moves the body by it on the next
// frame ONLY when bodyplace.json says "lean": 1, and says back what it used (S_LEAN_APPLIED). With "lean": 0
// (the built-in number) this part only measures: the recorder (rec.h) writes its numbers every frame, so what it
// WOULD do is on file from a walk before Tefa wears it doing anything.
//
// It writes no joint, hooks nothing, makes nothing. Its switch in off.txt: leanfix.
// NOT established: that moving the body's place by x moves the neck by x one frame later (the recorder's
// `lean_raw` must stay level while `lean_applied` changes: that is the check); the vault (never measured).
#pragma once

namespace vr8::leanfix {

struct Reading {
    bool ok = false;         // this frame was measured
    float behind_m = 0.0f;   // the neck behind the eyes, level, as drawn
    float raw_m = 0.0f;      // the same with our own move and the look-down shift taken out
    float standing_m = 0.0f; // the learned standing distance (0 until learned)
    float ask_m = 0.0f;      // what the body should sit further back by
    float applied_m = 0.0f;  // what the script used for this picture
    float down = 0.0f;       // how far the view looks down, 0..1
};

void pose();   // PrepareRendering post, once per frame, after the joint writer and ready::render_tick()
const Reading& last();

} // namespace vr8::leanfix
