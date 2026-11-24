// showspot.h -- SHOW a hand spot without doing it (2026-11-24, Tefa: "when hand freeze is on, to have these selectable - so if i
// select nr2, my hands automatically go on the gun in that grip zone and the pose both hands have in that zone ... without me having
// to release hand freeze"; approach A: "tune things without them being for real and once i'm finished tuning and try them out for
// real"). Hand Poser's SPOTS picker writes reframework/data/visceral_re8/show.json; while it names a hand, that hand's spot codes
// (bridge S_LEFT_SPOT / AREA, S_RIGHT_SPOT / AREA) are the shown ones, so Dock Poser adds that spot's wrist numbers and Hand Poser
// loads its pose, and the hand's arm target is put where the hand last REALLY sat at that spot (recorded here every time it is there,
// in the gun's frame, or the body's for a holster / first aid / map), or at the zone's middle if it never was. The reload itself is not
// touched: a shown spot is hands only. No heartbeat for SHOW_STALE_S, another gun, or both hands null = the real hands.
// Design: hand-poser-vr docs/superpowers/specs/2026-11-24-numbered-hand-spots-design.md.
#pragma once
#include "common.h"

namespace vn::showspot {

struct Shown { bool on = false; int spot = 0, area = 0, holster = 0; };

void frame();                  // UpdateBehavior, before pairs::frame: re-read show.json, drop it when stale or for another gun
const Shown& shown(bool left); // what SHOW asks of this hand now (on = false: the real hand)
void on_ik(MO* ik);            // in the IK chain right before dockpose: record the real place, or put the shown hand there

} // namespace vn::showspot
