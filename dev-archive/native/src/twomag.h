// twomag.h -- two magazines in the left hand: a handgun reloaded without ever being empty (2026-11-11, Fable, PC1).
//
// Tefa, 2026-11-11: "with handguns, to be able to take out a mag from pouch when a mag is still in the handgun. idea is to
// have a spare mag taken out with LG and LG held bringing my hand to the pistol, it docks under the mag with a spare mag in
// hand. then when i press B, i can pull out the mag from the gun and have now 2 mags in hand. once the mag that was in the gun
// is fully out, pressing LT puts the new spare mag in the chamber without the need to push it in by hand ... not leaving the
// left hand docked on the bottom of the new inserted mag, with the old mag still being held with LG. once LG is released ...
// the old mag is either dropped or put into any of the holster zones on the body ... it just dissapears from hand".
//
// The gun has ONE magazine (its "Magazine" joint), which reload.cpp moves. The other magazine in the hand is a copy drawn by
// visceral_re8_mag2.lua (the second shotgun shell's way: a copy of the gun's mesh, its body out of sight). This file only
// keeps WHICH extra magazine the hand holds and tells the Lua where the hand's hold is; the steps are reload.cpp's:
//   SPARE  LG at the pouch with a magazine still seated: a spare in the hand (the copy, in the hand's second place).
//          LG held to the gun's magazine: the hand docks on it. Right B: the gun's magazine comes out along the grip into the
//          hand (the joint, in the hand's first place): two in the hand. LT near the well: the swap.
//          LG let go: the spare is back in the pouch. The gun's magazine dropped to the floor meanwhile: the spare becomes
//          the ordinary magazine in the hand (it seats at the well by itself).
//   OLD    after the swap: the joint is the new magazine going in by itself; the copy is now the old one, in the first place,
//          looking as full as its own rounds. LG let go: it drops (the thrown magazine's copy takes over) or, in a holster
//          spot, is put away. The hand is not kept on the new magazine.
// The ammo is the ordinary reload's: the old magazine's rounds stay counted, as a dropped one's always did (reload.h).
#pragma once
#include "common.h"

namespace vn::twomag {

enum class Has { NONE, SPARE, OLD };
Has has();
void take_spare();                       // reload.cpp, the pouch grab with a magazine seated
void swap(int old_rounds);               // reload.cpp, LT: the spare is the gun's now, the old one stays in the hand
void clear(const char* why);
int rounds();                            // the extra magazine's own rounds (its look; a spare counts as full)
void publish(Vec3 hold_p, Quat hold_q);  // reload_pose.cpp, both pose points: the hand's magazine hold in the gun's space, for the Lua
bool drawn_pose(Vec3& p, Quat& q);       // where the Lua drew the extra magazine this frame, gun's space (the swap starts there)

} // namespace vn::twomag
