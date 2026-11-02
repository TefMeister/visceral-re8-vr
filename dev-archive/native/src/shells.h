// shells.h -- pump shotguns load two shells at a time by hand (2026-11-02, Opus).
//
// Tefa, 2026-11-02: "need to change how inserting shells works for shotguns, to have LG take out 2 shells in one go from the
// pouch and when left hand travels to the shell intake area, it docks and then LT puts the shells into the gun using games
// own hand movement. pouch only ever takes one ammo if there is only one left in the inventory or only room for one more".
//   pouch   LG takes SHELLS_PER_GRAB (2), or fewer: no more than are carried, no more than the gun has room for
//   port    with LG still held, the hand arriving at the shell port docks there (pairs.cpp, the "shell port" dock; it no
//           longer goes in by itself)
//   LT      puts the shells in one after another, each with the game's own finger movement (shellclip.cpp), SHELLS_STEP_S apart
//   LG off  lets go: the hand leaves the dock; shells still in the hand go back to the pouch (reload.cpp, as before)
// Which guns: single-round long guns with no breech to open (the W870, the M1897): weapons.cpp's ROUND + LONG + no breech.
#pragma once

namespace vn::shells {

bool port_gun();                          // the gun in hand loads through a shell port (the rules above apply)
int grab_count(int carried, int room);    // how many shells one pouch grab takes (carried < 0 = unknown / unlimited)
void dock_frame(bool lt_pressed);         // pairs.cpp, each frame the hand is docked at the shell port
void undock();                            // pairs.cpp, the hand left the shell port

} // namespace vn::shells
