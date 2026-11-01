// forearm.h -- the left forearm keeps ONE pose while a gun is in hand (2026-11-01, Tefa: "left forearm is teleport swapping
// between poses when using the rifle and needs to be just one single forearm pose").
// Measured on the simulator [verified-live 2026-11-01, n=1]: when the right hand let go of the rifle's bolt (the hand-back),
// L_Forearm_Twist_1..3 jumped 100 deg in one frame, then 51 and 52: the game works the twist joints out from the left hand's
// turn, and a quick turn flips them. So once a gun has been out FOREARM_SETTLE_FRAMES frames, the twist joints' local turns
// are kept and written back after the arm solves every frame, until the gun is put away or changed.
#pragma once
#include "common.h"

namespace vn::forearm {

void render_point();   // PrepareRendering post: keep / write the twist joints
void begin_render();   // BeginRendering pre: once more, after the arm solves

} // namespace vn::forearm
