// sleephands.h -- rebuild 2 (2026-11-26): a hand whose controller fell asleep stays where it was.
//
// Tefa (2026-11-26): "when the controllers go inactive, is there a way to just freeze hands in their current
// position? right now they teleport right to my face".
//
// Measured (the recorder's ctl lines, 2026-11-26 12:41, n=1, both controllers): a controller put down keeps
// reporting the spot where it lies for about 6 s, then reports the position 0 0 0 (a point at the headset's own
// origin: the hand at the face) until it is picked up; the loader goes on calling the controllers "in use".
//
// What it does: the bridge script flags a controller that reports exactly 0 0 0 (S_LEFT_ASLEEP, S_RIGHT_ASLEEP).
// While a controller is awake, that arm's joint rotations (as the loader's arm solver left them) are remembered
// every frame; while it is flagged asleep, the remembered ones are asked of the joint writer, so the arm stays as
// it was against the body. It stands down for a cutscene and for the game's own arms (Rose).
// A new player object starts from nothing (rule 7).
//
// It writes no joint itself (rule 3) and makes nothing (rule 4). Its switch in off.txt: sleephands.
#pragma once

namespace vr8::sleephands {

void pose();      // post-PrepareRendering, before the joint writer's flush

} // namespace vr8::sleephands
