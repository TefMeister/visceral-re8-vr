// gamearms.h -- rebuild 2 (2026-11-26, board row RE8-088): "the game's own arms are showing", and the SCENE LIST.
//
// Moved here from lua/visceral_re8_game_arms.lua (rule 11: per-frame work is native). That script was read as the
// reference and is archived; what was worn with it on 2026-11-26 is the behaviour kept:
//
// 1. THE CARRY. Tefa: "the idle pose for ethan when the controllers are down goes into the pose where he is
//    holding rose the correct way - if there is a way to have that hold for entire time Ethan is holding Rose?"
//    The game runs no event for the carry and sets none of the VR layer's flags; its marker is the object "pl5000"
//    (Rose) as a first-level child of the player's transform [measured 2026-11-26, n=3 runs]. While it hangs there
//    this part writes bridge slot S_GAME_ARMS = 1. re8_vr.lua (our dated line in update_hand_ik) asks the bridge
//    script and skips praydog's hand IK, so the arms play the game's hold-baby motions; fingers, sleephands and
//    carryarms read the same slot. Later "the game's arms" cases (a ladder, a scripted grab) get a line in CARRIED
//    or a new reason here: this is the ONE place that decides it.
//
// 2. THE SCENE LIST (Tefa: "it proves that cutscenes can be individually tuned"). One line per game event, by the
//    name the game gives it (app.GameEventActionController -> _GameEventAction -> _EventName). body: the body
//    stays drawn in it; head: the try at showing Ethan's head in a scene seen from outside his body (the script's
//    try never found the mesh controller; this one logs what it finds). The body also stays drawn for the whole
//    carry (the patting scene on the stairs hides it with no event).
//
// Rule set: reads, one bridge slot, and a mesh's draw flag. No joint, no object made, no request, no hook.
#pragma once

namespace vr8::gamearms {

void frame();        // UpdateBehavior pre, after ready::refresh(): the carry check, every few frames
void lock_scene();   // LockScene post (after the loader's own body hiding): the draw flags
bool carrying();     // true while something on the CARRIED list hangs on the player

} // namespace vr8::gamearms
