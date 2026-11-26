// doorsounds.h -- rebuild 2 (2026-11-26, from zero step 3): which of a door's sounds play.
//
// Tefa, 2026-11-26: "the door cannot have the normal 'open' sound, that plays when A is pressed or the door swings
// open just a tiny bit, it must only have the sound of the hinges, some creak, some gates have a metallic rusty
// sound, but we must mute the sound that is the first, door is now partly open sound".
//
// What the game has [read from re8.exe's type database with no game running, 2026-11-26, tdb-read.py; the reader's
// door-state numbers match the eight read in the running game on 2026-11-19]: a door plays its sounds through ONE
// method, app.DoorBehavior.CallSE (two forms: by an app.DoorSeTriggerType.Value object, by the name's hash), and
// there are exactly ten kinds:
//     Locked  CreakSlow  CreakStop  OpenKnob  OpenLock  OpenSlow  CloseCreakShort  CloseCreakLong  Close  CloseSoft
// WHICH of them is Tefa's "first, partly open" sound is NOT known: by its name it is OpenKnob [hypothesis, from
// the name alone]; the hinges would be CreakSlow / CreakStop (and OpenSlow?). So this part is built to find out
// and to be changed without a rebuild:
//   - it hooks both forms of CallSE, counts every kind, and the frame step logs each sound as it plays
//     ("door sound: OpenKnob (muted)"), so the first door in the headset names them by ear;
//   - it skips the kinds on the mute list. The list is reframework/data/visceral_re8/doorsounds.txt (kind names,
//     read again every 2 s in play); no file = MUTED_BY_DEFAULT below.
// Switch "doorsounds" in off.txt: nothing is hooked. The mute goes for every door, with or without Rose.
//
// RULE 8: the hooks may run on any of the game's threads, so they only read their own argument, compare it with
// numbers and addresses worked out beforehand on the main thread, and add to counters. No game call, no log
// line, no object from inside them.
#pragma once

namespace vr8::doorsounds {

void frame();     // UpdateBehavior pre: place the hooks once, re-read the mute list, log what played

} // namespace vr8::doorsounds
