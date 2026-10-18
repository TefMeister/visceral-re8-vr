// reload.h -- manual reloads for Village (2026-10-18). Tefa the same evening: the RE7 reload "for re8 village ... port over
// the re7 reloading systems". Moved over from Visceral RE7's reload.cpp (itself built on Visceral RE2's, worn there,
// written from Andyalpa's RELOADED as the specification). Same controls as RE2 / RE7:
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
bool round_in_hand();    // a shell / round is in the left hand
bool in_pouch();         // the left hand is in the ammo spot
void on_racked();        // rack.cpp: the slide / pump cycled: rounds waiting for it go in

} // namespace vn::reload
