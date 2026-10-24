// body.h -- the visible body turns like Visceral RE2's (Tefa idea 6, 2026-10-24: "get the body to turn like it does in
// re2, it is much more natural, when walking and looking around while standing still").
//
// How RE2 does it (REFramework FirstPerson::update_player_body_rotation): every frame the player's yaw is turned toward
// the look direction by a step that grows with the angle between them, so the body lags and catches up smoothly. In
// Village the game's own first-person code decides the player transform's yaw (the camera and the aim hang off it), so
// turning the TRANSFORM would turn the view. This turns only what is DRAWN: after the animation has posed the skeleton,
// every joint is turned about the vertical axis through the player's feet by an offset theta that lags its target:
//   walking:  the direction of travel (back-pedalling: the look direction)
//   aiming:   the look direction
//   standing: nothing, until the head is more than BODY_STAND_DEADZONE_DEG from the body; then the body comes round to the
//             look, gently, all the way (2026-10-25: it used to stop at the slack's edge and stay turned)
//   a menu / the inventory up: off (2026-10-25)
// The arm IK runs after this write (praydog's hand targets are separate transforms), so the hands stay on the controllers.
// Whether the engine keeps the write until the frame is drawn is measured every frame (the root joint read back at
// PrepareRendering) and logged once a second, so a run says "held" or "undone" by itself.
#pragma once

namespace vn::body {

void frame();          // UpdateBehavior pre: the target and the lag
void late_point();     // LateUpdateBehavior post: turn the skeleton
void render_point();   // PrepareRendering post: read the root back (did the write hold?)
void install();        // once: hooks the inventory's open / close calls
void probe_types();    // first frame: which game types own calculateBodyDirection / set_bodyDirectionTarget / getCameraYaw
float applied_yaw();   // the offset drawn this frame (radians)

} // namespace vn::body
