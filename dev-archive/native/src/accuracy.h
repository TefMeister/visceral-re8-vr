// accuracy.h -- a handgun's accuracy from how it is held and how fast the player moves (2026-11-11, Fable, PC1).
//
// Tefa, 2026-11-11: "one handed running is 30%, walking is 50%, standing still is 75%, extra mag in hand, running is 40%,
// walking is 65%, standing still is 85%, both hands on the gun - LG docked on the mag, running is 50%, walking 80%, standing
// still 100%" (and earlier the same day: "gripping the gun with an empty hand has 100% no bullet spread accuracy").
//
// The lever is the scope project's (re-village-scope-vr dossier 9bk / 9bl, proven on the sniper rifle): the game scatters a
// bullet's rotation BEFORE it builds the bullet, so the rotation handed to app.WeaponGunCore.createBulletImple is replaced at
// its entry. Here it is replaced by the clean aim (the shortest turn from +Z onto the ray createBullet was given, the engine's
// own convention) turned by a random angle inside a cone of (100 - accuracy) percent of ACC_CONE_DEG. So 100% is dead
// straight and the game's own scatter no longer counts for these guns: the percentages mean the same thing aimed or not.
// Which guns: magazine-fed handguns, in VR. Every other gun keeps the game's own scatter (the rifle: the scope plugin's fix).
//   hold   one hand / the left hand on the gun with a magazine in it / both hands on the gun (reload::left_at_gun: docked on
//          the magazine, the game's own two-handed grip, or LG held within ACC_AT_GUN_M of the well)
//   move   the player's speed over the ground: under ACC_WALK_MPS still, under ACC_RUN_MPS walking, else running
// Every shot is logged (hold, movement, speed, percent, the angle it got and the angle the game would have given).
#pragma once

namespace vn::accuracy {

void install();   // first game frame: the two bullet hooks
void frame();     // UpdateBehavior pre, after reload::frame(): this frame's hold and movement

} // namespace vn::accuracy
