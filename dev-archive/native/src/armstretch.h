// armstretch.h -- rubber arms: the left arm grows to keep the left hand on the gun (2026-11-08, Tefa's ideas list, idea 15:
// "LG must hold on to the gun whatever happens or how wide apart motion controllers actually are. Also hands need to stretch to
// keep the left hand on the weapon handle at all times, even if they look rubber hands and visibly look stretched").
// The grip already stays while LG is held, at any distance (re8_vrz_begone_grip.lua, 2026-10-25). What was left: past the arm's
// reach the game's arm solve stops short and the hand hangs off the gun. So, while the left hand is held on the gun (a docked
// spot, or the two-handed grip), after the arm solves: when the hand's target is further from the shoulder than the arm is long,
// every joint from the elbow down to the hand is moved out along its bone by the same factor (up to ARM_STRETCH_MAX), which puts
// the straightened arm's hand on the target. Eased in and out, so the arm never snaps. Untested in the game (2026-11-08).
#pragma once
#include "common.h"

namespace vn::armstretch {

void render_point();   // PrepareRendering post: after the arm solves (and after the forearm hold), stretch or put back
void begin_render();   // BeginRendering pre: the same lengths once more

} // namespace vn::armstretch
