// whichpart.h -- which part of the gun takes the left hand when LG is pressed inside more than one grip zone.
//
// 2026-11-23 (Tefa: "hands land where they should with LG"). By robot hands the F2 gave the bolt hold with LG at the magazine's
// middle and at the front grip's middle (2 of 3 approaches), and the Dragoon gave the magazine with LG at the charging handle
// (the next LT pulled the magazine out instead of racking): the magazine took every hand inside its ball, unless a rack was
// due, then the bolt took every hand inside ITS ball; the front grip was not asked at all.
//
// The rule now, one for every gun: of the zones the hand is inside, the one whose MIDDLE is nearest for its size wins
// (distance / reach; the pistols' two slide spheres have chosen like this since 2026-10-28). A rack that is due, or a bolt
// mid-cycle, counts as nearer by WHICHPART_DUE_BIAS (Tefa 2026-11-01: "when a rack is due and the hand is near both, the bolt
// wins"): it still wins the overlap, but no longer at the very middle of the magazine. The front grip is asked on long guns only.
#pragma once

namespace vn::whichpart {
enum Part : int { NONE = 0, MAG = 1, RACK = 2, GRIP = 3 };
Part nearest();                // the winner for the left controller right now (NONE = inside no zone)
const char* name(Part p);
}
