// doors.h -- doors and gates pushed open by the hand and the body, as in Visceral RE2 / RE3 (2026-11-16, Tefa: "and re8 as
// well if you can, although re8 doors work differently"; 2026-11-18, worn: "i could not open gates by hand, they still opened
// by themselves with me quite far away": nothing of this was built yet, that was the plain game).
//
// What Village's doors are (read live on the simulator 2026-11-16, modding-notes/2026-11-16-village-doors-what-they-are.md):
// every leaf is an app.DoorBehavior (a gate's two leaves are two of them under one app.DoorDoubleBehavior); the leaf turns on
// its joint "_00" about the door's own up; A opens a gate fully, 0 -> 90 degrees in ~1.6 s; while it opens the game writes
// the joint every frame, and once open it STOPS writing it (our own write then holds). So the game's angle is read back the
// way RE2's doorpush reads it, but only on the frames the game wrote the joint (it differs from ours): those say "the game is
// opening it" or, falling, "the game is closing it".
// The rule, RE2's: whoever opens the door (A, the game's own push, or the hand touching a shut leaf, which presses A for the
// game through re8_vr.lua's pad, bridge S_DOOR_PRESS_SEQ), it is DRAWN open only 1 degree; from there the hands and the body
// push it, never less than the body needs to pass, and it goes back down with the game when the game closes it.
// Up to DOORS_MAX_LEAVES leaves near the player at once (both leaves of a gate).
#pragma once

namespace vn::doors {
void frame();         // UpdateBehavior (pre): the leaves near the player, the hand touch that opens a shut one
void late_point();    // LateUpdateBehavior (post): read what the game wrote, push with the hands and the body, draw ours
void render_point();  // BeginRendering (pre): draw ours again
} // namespace vn::doors
