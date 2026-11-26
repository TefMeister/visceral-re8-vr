// jointwriter.h -- rebuild 2 (design item 2): THE joint writer. RULES 1, 2 and 3 live here.
//
//   Rule 1: joints are written at PrepareRendering only (post, after praydog's layer). Never at BeginRendering:
//           a joint written there stops the engine drawing other things anew (b177, the lift glitch, measured).
//   Rule 2: no hook on via.Joint's or via.Transform's setters; this file calls them, nothing intercepts them.
//   Rule 3: one writer per joint per frame. A part asks ("this joint, this local rotation"); flush() writes each
//           joint once, parts in the fixed order of `Owner` below (who runs last is decided HERE, in one table,
//           not by load order). A second ask for the same joint in one frame is refused and logged once per pair.
//
// No part calls a joint setter itself. tools/build.sh fails the build when a source file other than this one
// names a via.Joint setter, or when any names BeginRendering.
#pragma once
#include "base.h"

namespace vr8::jointwriter {

// The order joints are written in: a part lower in this list wins a joint over a part above it ONLY by being the
// one that asked; two asks for one joint in a frame are a fault, and the FIRST in this order is the one written.
enum class Owner : int {
    FingersRest = 0,     // fingers.cpp: an empty hand's fingers held still
    CarryArms,           // carryarms.cpp: the game's own arms held steady while Rose is carried
    SleepHands,          // sleephands.cpp: an arm held where it was while its controller is asleep
    SpineStill,          // spinestill.cpp: the lower spine's turn toward the view taken out again
    Count,
};
const char* owner_name(Owner owner);

void ask_local_rotation(Owner owner, MO* joint, const Quat& rotation);
bool read_local_rotation(MO* joint, Quat& out);
MO* joint_by_name(MO* transform, const wchar_t* name);

void flush();     // post-PrepareRendering, once per frame; plugin.cpp calls it after every part has asked

} // namespace vr8::jointwriter
