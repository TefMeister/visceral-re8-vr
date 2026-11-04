// dockreport.h -- where the drawn left hand actually lands when LG takes a part, measured (2026-11-04, Opus).
//
// Tefa, 2026-11-04: "making sure the hands actually land where they have to with LG". Until now that was judged from a
// picture taken from behind the player, which could not tell a hand on the fore-end from one floating beside it. This
// measures it: while the left hand is docked (the slide / pump / bolt, the magazine, a handgun's handle, the drum, the
// GM 79's breech, or the front grip when two-handed), after the arm is solved, the PALM (half way from the L_Hand joint to
// the L_MiddleF1 joint) is compared with the centre of that part's zone (the same centre the grab tests and the menu draws).
// The gap is written in the gun's own axes (x right, y up, z toward the muzzle), with the hand's turn in the gun's frame.
// So a correction can be read off directly: dock_poses.json moves the hand by the opposite of the gap.
// Output: reframework/data/visceral_re8/dock_report.tsv (twice a second while docked) and one log line per hold
// ("[visceral-re8] dockreport: ..."), 0.4 s after the hold starts so the eases have settled.
#pragma once

namespace vn::dockreport {

void render_point();   // BeginRendering pre, after the arm solve and every hand writer

} // namespace vn::dockreport
