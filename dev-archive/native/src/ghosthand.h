// ghosthand.h -- Ghost Hand BeG0nE recorder for Visceral RE8 (2026-10-19), moved over from visceral-re2-vr's ghosthand.cpp.
// Tefa 2026-10-19: "please have BeG0nE tools automatically log everything". Writes
// %LOCALAPPDATA%\BeG0nE\ghost-hand\visceral-re8-vr_<date>.ghl in the Lanes recorder's line format while the headset is
// live (the bridge says so); the Lanes rider files it, and starts the game recording when a log starts. A flat run
// writes nothing.
//
// Space: everything in the REAL ROOM (OpenXR tracking space, metres): the controllers from the bridge as they are, the
// game's hands and the gun's moving parts carried from the game world through the camera (bridge::world_to_room).
// Gestures logged with start / done / fail: rack, pump, bolt (rack.cpp), mag, shell (reload.cpp).
#pragma once
#include "common.h"

namespace vn::ghosthand {
void render_point();                                  // PrepareRendering post: one frame of samples
void event(const char* gesture, const char* what);    // "start" | "done" | "fail" | "cancel"
void value(const char* name, float v);
void shutdown();
} // namespace vn::ghosthand
