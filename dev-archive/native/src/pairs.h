// pairs.h -- numbered hand pairs (2026-10-25, Tefa: "a green sphere means activation area and yellow spot means where the hand
// lands after being activated in that sphere. with more spots, they have to be numbered, number 3 green sphere must send the
// hand to nr 3 yellow spot", then "doesn't have to be colours. as long as somehow i can tell that a spot is activation spot and
// where it takes the hand afterwards, and what it is for"). Each pair: a number, a name ("eject magazine"), the gun it is for
// ("any" or its number), an ACTIVATION sphere and a LANDING spot, both offsets from the gun hand in the gun's own axes (x right,
// y up, z forward, metres), as zones.json's. The left grip pressed inside pair N's activation sphere sends the left hand to pair
// N's landing spot (smooth.cpp eases it there with the arc) and keeps it there while the left grip is held. The numbers live in
// reframework/data/visceral_re8/pairs.json, written by the Grab Zones window; "show": N picks the one pair drawn on the gun
// (a big sphere = activation, a small dot = landing, a dotted line between them: lua/visceral_re8_zones.lua).
#pragma once
#include "common.h"

namespace vn::pairs {

void frame();      // UpdateBehavior, after rack: the file, the take and the release, the shown pair's spheres
bool active();     // the left hand belongs to a pair now
// where the hand lands, in the gun hand's frame (rp, rq = the gun hand's IK target), and its turn there; false = no pair
bool landing(const Vec3& rp, const Quat& rq, Vec3& rel, Quat& qrel);

} // namespace vn::pairs
