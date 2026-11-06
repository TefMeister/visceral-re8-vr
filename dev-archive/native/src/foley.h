// foley.h -- the game's raise / lower handling clicks kept quiet while the Wolfsbane is in the left hand (2026-11-06, Opus).
//
// Tefa, 2026-11-06: "when gun is held in left hand, just moving right hand around the back of the weapon produces a gun sound of
// some sort, little bit like a reloading sound but not sure, like some weapon parts moving".
// [hypothesis] The game still switches the upper body between READY (21xx), AIM (22xx, 2421) and LOWERED (23xx) as the gun's
// pitch changes, and app.WwiseWeaponMotionSequence plays each switch's weapon foley (the log of that run heard
// SND_MOT_RI3008_SE_BACK_DEFAULT on motion 2106). With the gun held by our left hand those switches are meaningless and come
// often. The scope mod silences the same families while the sniper rifle is out (re8_vrz_scope_sounds_menu.lua, worn
// 2026-09-27); this does it natively while gate::holding(). Each silenced click is logged (motion id), so the wear says whether
// this was the sound.
#pragma once

namespace vn::foley {

void install();   // first game frame: hook app.WwiseWeaponMotionSequence.weaponTrigger / manualTrigger

} // namespace vn::foley
