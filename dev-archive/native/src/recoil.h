// recoil.h -- physical recoil on the VR hands, Andyalpa's way (port of re8_vr_recoil.lua, Hands Off pack). 2026-10-15.
//
// Each shot of the player's gun (app.WeaponGunCore.shoot) queues a kick. Once per frame the kick ramps in over
// attack_duration (a quarter sine), then a damped spring brings it back, with stiffer damping right after a burst
// (sustained_window) and extra damping as it nears rest (spring_settle_mult); the last bit fades out over 45 ms.
// The offset is a wrist pitch (muzzle climb), a wrist yaw and a small lift, scaled by the gun (per-weapon intensity,
// class profile: handgun ... minigun), by one or two hands (one hand kicks harder, heavy guns most), and for
// full-auto guns by auto_scale. It is written into the hand IK targets right before the game solves each hand
// (app.AnimIK2Bone.calc): the right hand gets the kick, and the left hand, when it supports the gun, keeps its
// place relative to the right hand so both move together. Optionally skips the game's own camera shake.
//
// Settings: Andyalpa's file re8_vr/re8_vr_recoil.json, same keys. lua/visceral_re8_menu.lua draws the menu and writes
// the file; this reads it back whenever it changes.
#pragma once

namespace vn::recoil {

void install();        // hooks shoot, AnimIK2Bone.calc and the camera shake (first game frame, after bridge::install)
void frame();          // UpdateBehavior pre: settings file check
void physics_point();  // UpdateMotion pre and LateUpdateBehavior pre: the once-per-frame physics step

} // namespace vn::recoil
