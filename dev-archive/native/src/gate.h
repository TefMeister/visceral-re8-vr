// gate.h -- the M1851 Wolfsbane loaded through its cover, by the RIGHT hand (2026-11-01, Tefa's plan):
//   "RT to shoot, hammer cocks automatically with the game animation ... B to open the drum guard when need to reload. when the
//   guard is open on wolfsbane, LG cannot get ammo from ammo pouch, instead LG on ammo pouch takes the hand to the base of the
//   drum, as does LG anywhere on the weapon, while the guard is open. LG on the weapon releases right hand which can take ammo
//   from the ammo pouch on the left hip and bringing right hand with RG held to the back of the weapon docks it and RT this
//   time inserts the bullets. LT is used to rotate the drum after each bullet insert and has to be rotated, which makes the old
//   casing fall out automatically, regardless of the angle, only first bullet insert doesn't need the drum rotated with LT.
//   once all the bullets are in, or as many as was in players inventory at the time of getting them from the pouch ... right
//   hand automatically goes back on the grip and thumb closes the bullet guard. left hand will stay docked on the drum until LG
//   is released, LT wont do anything once the bullet guard is closed. weapon can still be shot while LG is being held, but
//   when bullet guard is closed, right hand steers the gun. while bullet guard is open, the weapon is frozen in left hand like
//   the rifle with right hand bolt racking."
// The phases:
//   OFF       the game's own hold (right B opens the cover: breech.cpp)
//   HELD      cover open, LG taken: the gun trails the left controller slowly (rack_right.cpp's way), the left hand drawn at the
//             base of the drum; the right hand free: RG at the left-hip pouch takes rounds (as many as the free chambers and the
//             carried ammo allow), RG held near the cover docks it there; RT there puts one in; LT turns the drum (needed
//             between rounds; each turn drops one spent casing)
//   RETURN    all in (or right B): the right hand glides back onto the grip, then the thumb closes the cover
//   HANDOVER  the gun eased back onto the right controller, the left hand riding it
//   STAY      the cover shut, the right hand steers, the left hand stays on the drum until LG is let go
// First cut: the hand places and the drum's turn are guesses, tuned live in lid_swing.json ("left", "right", "cyl_axis").
#pragma once
#include "common.h"

namespace vn::gate {

void frame();               // UpdateBehavior, after breech::frame()
void on_ik(MO* ik);         // ik.cpp, LAST
void late_point();          // LateUpdateBehavior post / PrepareRendering post / BeginRendering pre: the gun, the drum's turn
bool here();                // the gun in hand is the cover gun
bool holding();             // HELD or RETURN: the gun is in the left hand (no shot, no holster, no pouch for the left hand)
bool owns_left();           // the left hand is drawn by us (HELD to STAY): the grip script keeps off it
void close_request(const char* why);   // right B while held: the right hand back to the grip, then the cover shuts
void abort(const char* why);
void tune(const Vec3& left, const Vec3& right, const Vec3& cyl_axis, const Vec3& hammer);   // from lid_swing.json (breech.cpp)
// 2026-11-01 23:4x: HAMMER, the cover shut: LG at the hammer docks the left palm there; a shot leaves the hammer down (no next
// shot) until LT pushes it back; B opens the cover and the hand goes to the drum
bool hammer_down();
// 2026-11-02 (Tefa: "in hand poser, docking left hand on the hammer doesn't show that the hand is docked at all, same with the
// right hand when it docks on the gun to insert bullets"): the spots told to Hand Poser (pairs.cpp writes them)
int left_spot();    // 10 = the hammer, 6 = the drum (the gun held for loading), 0 = none of ours
bool right_at_cover();
void tune_hammer(const Vec3& axis, float deg);   // lid_swing.json "hammer_axis", "hammer_deg": the hammer's turn from cocked to down

} // namespace vn::gate
