// righthand.h -- the right hand keeps ONE relaxed pose while no weapon is out (2026-11-01, Tefa: "stop right hand animation
// open/close when walking with no weapon out"). The walk animation flexes the right fingers; with no gun in hand they are eased
// (RIGHT_STILL_SEC) to the skeleton's own rest turn (BaseLocalRotation, Village's relaxed curl) and written after the animation
// every frame; a weapon drawn eases them back to the game's.
// 2026-11-01 23:3x (Tefa: "left hand is still animating while walking"): the LEFT fingers the same way, whenever the left
// hand is free (nothing held, no Hand Poser, not opening toward a part).
#pragma once
#include "common.h"

namespace vn::righthand {

void render_point();   // PrepareRendering post
void begin_render();   // BeginRendering pre: once more, after the arm solves

} // namespace vn::righthand
