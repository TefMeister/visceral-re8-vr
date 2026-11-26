// leanrec.h -- rebuild 2 (2026-11-26, DEV ONLY, comes out when the body pin is built): a silent recorder.
//
// Tefa, in the village: "when i run and stop, Ethan's whole body get's pushed forward so for less than a second
// i'm looking through his body, like from the centre of it"; the same at a vault and when a cutscene hands
// control back. Two tries at a "body pin" in the bridge script moved the body wrongly (b183: the Head joint read
// 72 cm off; b184: the joints read there swung 30 to 46 cm with plain head movement, because that point of the
// frame is before the body is posed). So this measures first, at the point where the joint writer writes
// (PrepareRendering post: the body is posed, the hands' solve is done), and changes NOTHING:
//   how far the neck, the upper spine and the hip are behind the eyes (level, along the view), and to the side,
//   as the least and the most seen in each half second, with how fast the player moved.
// One log line per half second in which anything moved more than a few centimetres. Switch "leanrec" in off.txt.
#pragma once

namespace vr8::leanrec {

void pose();     // PrepareRendering post; reads only

} // namespace vr8::leanrec
