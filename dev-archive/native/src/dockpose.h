// dockpose.h -- the left hand's wrist, per gun and per docked spot (2026-10-28, Tefa: "we need Dock poser to be what Grip Zones
// has for turning the wrists and all those settings, while the left hand is actually docked on any of the weapon grip spots, mags
// and bullets from the pouch included"). The Dock Poser window (grip-zones-vr/dockposer/) writes
// reframework/data/visceral_re8/dock_poses.json: {"<gun number>": {"<spot>": {"x", "y", "z" (metres), "rx", "ry", "rz" (degrees)}}},
// the spot being the one Hand Poser reads (bridge S_LEFT_SPOT: 3 slide / pump / bolt, 4 magazine, 5 handle, 6 drum, 7 insert,
// 8 slide from the left, 9 rounds from the pouch, 1000+N pair N's landing spot). Whoever placed the left hand (rack, reload,
// pairs, smooth), the hand is then moved and turned by that spot's numbers in the gun's own axes (x right, y up, z forward),
// eased in and out so a change of spot never snaps.
#pragma once
#include "common.h"

namespace vn::dockpose {

void on_ik(MO* ik);   // ik.cpp: last, after smooth: the left arm is about to be solved

} // namespace vn::dockpose
