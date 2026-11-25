// fingers.h -- rebuild 2 (2026-11-26): an empty hand's fingers stay still.
//
// Tefa (2026-11-26, the bare base): "hands animate open/close again when moving with an empty hand, both hands do
// it". The game's walk motions move the fingers; in VR the hands are the player's own, so the fingers flap.
//
// What it does: per hand, once the player has stood still for REST_STILL_S with that hand empty, the fingers'
// local rotations are read ONCE (the "rest" pose, the game's own standing fingers). From then on, while that hand
// is empty and the hands are the player's (ready.h), those rotations are asked of the joint writer every frame.
// It stands down by itself for a cutscene, the game's own arms (Rose), a resting controller, and for the right
// hand while it holds a weapon. A new player object starts from nothing (rule 7).
//
// It writes no joint itself (rule 3) and makes nothing (rule 4). Its switch in off.txt: fingers.
#pragma once

namespace vr8::fingers {

void pose();      // post-PrepareRendering, before the joint writer's flush

} // namespace vr8::fingers
