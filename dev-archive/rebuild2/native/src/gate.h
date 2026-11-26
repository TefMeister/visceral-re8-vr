// gate.h -- rebuild 2 (2026-11-26, with the doors): THE REQUEST GATE. RULE 5 lives here.
//
// Anything that makes the game start, queue or build something (open a door, an equip or item request, a motion
// request, a sound trigger, switching a thing's collision) is ASKED of this file and made by it:
//   - on the main thread, at ONE fixed point of the frame (UpdateBehavior pre, right after the player is found);
//   - never from a render callback, never from a hook (a hook may only count; the part's frame step asks);
//   - never while there is no player (a load, the title screen): what was asked then is dropped and counted;
//   - at most once per ask (no timers that repeat a request "to be safe": a part that wants it again asks again);
//   - counted per kind, one log line a minute while anything went through.
// It rests on the reading of the crash at re8.exe+0x4151C23 (note 2026-11-25c: a request the game had queued for
// a script and found dead) [inferred-static + hypothesis]. b178 had no such place: 9 scripts made requests
// from wherever they happened to run.
#pragma once

#include <functional>

namespace vr8::gate {

enum class Kind : int {
    DoorOpen = 0,     // doors.cpp: the game's own "open this door" for a door a hand is on
    DoorSolid,        // doors.cpp: an open leaf's solid parts off, and on again when the game shuts it
    Count,
};

void ask(Kind kind, std::function<void()> request);   // from a part's frame step; made at the next run()
void run();                                           // plugin.cpp, UpdateBehavior pre, after ready::refresh()

} // namespace vr8::gate
