// doors.h -- rebuild 2 (2026-11-26, from zero step 3, board row RE8-087): doors open at the hand.
//
// Tefa, 2026-11-26: "pushing doors open by hands, the only thing is walking with rose to the very first door, i
// cannot use my hands so the door must open with me just walking into it"; and of b142 (2026-11-19): "the door
// opening sound, it has to come after the hand is actually on the door". Asked 2026-11-26 whether a hand hanging
// at the hip that brushes a door he walks into should open it: "yes".
//
// Written fresh. The reference READ for it: b178's src/doors.cpp + lua/visceral_re8_doors.lua and the notes of
// 2026-11-16 and 2026-11-19 (everything known there was seen on the Duke's GATE on the simulator; an ordinary
// house door has never been seen). The leaf's angle sums (which side of the leaf a point is on, how far a hand
// or the body pushes it) are carried over from b178 after a read-through.
//
// What it does:
//   1. NEVER FROM AFAR. The game opens a door when the player walks into the leaf's push sensor
//      (app.InteractDoor.OnOverlapDoorPushCollider). That call is skipped ...
//   2. ... EXCEPT WHILE THE GAME'S OWN ARMS SHOW (Rose is carried: gamearms.h), or the headset / controllers are
//      not in use: then the game's own walk-in open stands and this part does not touch that door at all.
//   3. A HAND ON A SHUT DOOR, moving into it, asks the request gate for the game's own door start
//      (app.InteractDoor.StartInteractDoor(player), the A button's path) on that leaf. Locked: nothing.
//   4. FROM THERE THE LEAF IS OURS until the game shuts the door: drawn 1 degree open, then pushed by the hands
//      and by the body as far as they go (never back); its solid parts are off meanwhile so Ethan can walk
//      through (the game counts the door open at its own angle, where the leaf would be out of the way).
//      A door found already open is left alone until it has been seen shut once.
//   The door's sounds: doorsounds.h.
//
// On the frame: the walk-in hook only reads one flag and counts (rule 8); the door start and the collision
// switch go through the request gate (rule 5); the leaf goes through the joint writer (rules 1-3); nothing is
// made (rule 4); switch "doors" in off.txt (rule 10). doors.txt in the data folder: the hand's reach and the
// body's reach in centimetres, read again every 2 s in play.
#pragma once

namespace vr8::doors {

void frame();     // UpdateBehavior pre, after the request gate ran: find the near doors, touches, pushes
void pose();      // PrepareRendering post, before the joint writer's flush: the leaves we draw

} // namespace vr8::doors
