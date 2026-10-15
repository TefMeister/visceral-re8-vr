// haptics.h -- the game's rumble on the controllers, Andyalpa's way (port of re8_vr_haptics.lua, Hands Off pack).
//
// The game asks the pad to rumble through app.HIDVibrationManager.OrderVibration (two overloads). praydog's
// re8_vr.lua forwards each order to the two controllers; Andyalpa's script then filtered those forwards:
//   - the LEFT hand only feels a shot while it supports the gun (docked on it, or left grip held near the right hand)
//   - shot strength scaled (Low 0.45 / Medium 0.80 / High 1.20, clamped to 1.5)
//   - full-auto guns: one short tick per period instead of a continuous buzz, each hand once per tick
//   - inside a holster or head-flashlight zone, rumble passes unscaled (those are grab pulses, not shots)
// Here the plugin hooks both overloads itself, does the forward and the filter in one place, and hands the result
// to the bridge Lua to fire; our copy of re8_vr.lua stands its own two forwards down while S_NATIVE_HAPTICS is 1.
// The game's own pad rumble is never touched.
#pragma once

namespace vn::haptics {

void install();    // hooks OrderVibration (first game frame, after bridge::install)
void frame();      // once per frame: two-hand state, shot context expiry

} // namespace vn::haptics
