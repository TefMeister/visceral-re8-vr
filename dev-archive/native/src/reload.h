// reload.h -- manual reloads for Village (2026-10-18). Moved over from the RE7 RELOADED mod's reload (built on Visceral
// RE2's, worn there, written from Andyalpa's RELOADED as the specification). Same controls as RE2 / RE7:
//   right B          the magazine comes out (the gun reads empty; its rounds stay with that magazine)
//   left grip in the ammo spot on the left hip   a magazine in the left hand (Andyalpa's Hands Off "ammo_left" spot,
//                    which buzzes and was waiting for a reload; our own left-hip spot if his is switched off)
//   bring it to the gun   it goes in: the dropped magazine's rounds come back, topped up from the ammo carried
//   let go of the left grip with it in hand   it drops
//   A magazine into a gun that was EMPTY needs a rack (rack.cpp) before it fires; shells into an empty pump gun a pump.
// Single-round guns (pump shotguns, GM 79, Wolfsbane): each grab is one round, brought to the gun.
// Village differences: where things go in is measured from the gun hand in the room (settings.h DOCK_*), because
// Village's gun parts are not known yet; the magazine is only drawn moving when its joint is found (logged).
// Ammo is Village's own model (player.cpp, read from the game's type list 2026-10-18): the gun's item record holds its
// rounds, the gun's own reload() tops it up from the carried ammo, its switchMagazineDisp hides the magazine.
#pragma once
#include "bridge.h"
#include "common.h"

namespace vn::reload {

void install();          // hooks the game's own reload request if one of the known names exists (first game frame)
void frame();            // UpdateBehavior pre: right B, the ammo spot, the timers, the ammo
void late_point();       // LateUpdateBehavior post: the hand checks, pose the magazine joint
void render_point();     // PrepareRendering post: pose it again

bool managed_now();      // the gun in hand reloads by hand
bool mag_out();          // the magazine is not seated
bool session_active();   // a reload is under way
bool mag_in_hand();      // a magazine is in the left hand (or going in)
int mag_rounds_out();    // 2026-11-05: the rounds in the magazine that is out of the gun (its OWN count; a fresh pouch one as full as the carried ammo allows); -1 = seated / none (magdisp.cpp)
bool round_in_hand();    // a shell / round is in the left hand
bool hand_on_mag();
bool hand_near_mag();     // the left hand within MAG_GRAB_M of the seated magazine (the rack and the grip keep off)      // the left hand holds the magazine going in, or seated, until LG is let go
float pouch_dist(bridge::Hand h);   // 2026-11-01: a hand's distance from our left-hip pouch spot (m)
bool in_pouch();         // the left hand is in the ammo spot
void on_racked();        // rack.cpp: the slide / pump cycled: rounds waiting for it go in
void on_ik(MO* ik);
// 2026-10-27 (breech.cpp): LT at a revolver's drum puts one round in (false = none went in); a round taken out of the GM 79
// by hand goes back with the carried ammo and is loaded again first
bool load_round();
void pocket_round();
// 2026-10-27: a revolver's rounds in the left hand (0 = none), and one of them into the drum (breech.cpp, LT on the drum)
int rounds_in_hand();
bool insert_from_hand();
void grab_from_pouch();          // 2026-11-02: a pouch grab without a fresh LG press (breech.cpp: LG held in with the spent case)
bool port_center(Vec3& out);     // 2026-11-02: the shell port, world (pairs.cpp's shell port dock)
bool insert_direct();
bool insert_direct_possible();   // a round could be taken from the carried ammo now         // 2026-11-01: one round from the carried ammo straight into the open drum (LT, no pouch trip)      // ik.cpp: keep the left hand on its controller while it carries a magazine / round

} // namespace vn::reload
