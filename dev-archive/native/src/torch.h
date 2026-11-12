// torch.h -- the torch you hold (2026-11-12, Tefa; the same design as Visceral RE2 / RE3: "manual flashlight, an actual
// flashlight one can hold in hand ... flashlight is in the left shoulder spot with LG ... tap LG in the shoulder holster to
// bring it out, tap LG again to put it back ... LT switches it on/off in both hand and shoulder spot. long weapons cannot
// be two handed while flashlight is held ... but can reload weapons with the flashlight out"; the grip by the wrist).
//
// Village's light is the game's HandLight (app.PlayerHandLight + a "HandLight" scene object with the IES light), which
// Andyalpa's holster script already powers and aims from the head (its head-zone flashlight). With this on, the script's
// head zone steps aside and it powers the light as THIS says, and while the torch is in the hand it puts the beam where
// this says: out of the left fist, along the controller (bridge S_TORCH, S_TORCH_POS, S_TORCH_ROT). No torch model yet:
// our own, made in Blender with Tefa, comes later.
#pragma once

namespace vn::torch {
void frame();       // UpdateBehavior pre, after the reload and the rack: the buttons, the grip, the beam's place
bool in_hand();     // the torch is out of its spot (handstate.cpp: no two-handed grip on a long gun)
} // namespace vn::torch
