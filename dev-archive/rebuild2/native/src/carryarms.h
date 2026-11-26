// carryarms.h -- rebuild 2 (2026-11-26): the game's own arms stay steady while Ethan carries Rose.
//
// Tefa (2026-11-26): walking forward and sideways with Rose "she swings a lot", walking backward "is how it should
// always be". Measured (the recorder's skel lines, joint heights against the eye camera, 2026-11-26 11:16-11:18,
// n=1 run, 40 windows): hip, spine, neck, head and shoulder 0 cm; upper arm 1; forearm 5 (left) and 3 (right);
// hand 6. So the swing is the walk motions' own arm travel from the shoulder down, not the body.
//
// What it does: while the game's arms are showing (bridge S_GAME_ARMS) and no cutscene runs (the patting scene on
// the stairs raises the cutscene flag and must play as the game made it), the arm joints' local rotations are
// read once, when the player has stood still AND the arms themselves have not moved for REST_QUIET_FRAMES (so a
// turn on the spot or the tail of a blend is never taken for the rest pose). From then on those rotations are
// asked of the joint writer every frame, eased in and out against the motion's own pose over EASE_S.
// A new player object starts from nothing (rule 7).
//
// It writes no joint itself (rule 3) and makes nothing (rule 4). Its switch in off.txt: carryarms.
#pragma once

namespace vr8::carryarms {

void pose();      // post-PrepareRendering, before the joint writer's flush

} // namespace vr8::carryarms
