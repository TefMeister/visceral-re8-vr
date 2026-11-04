# Where the left hand lands with LG, and the zone sizes (2026-11-04 22:35-23:10, Opus, home PC, OpenXR Simulator)

Tefa: *"making sure the hands actually land where they have to with LG"*, then *"please also tweak the activation zones to be
big enough just to not interfere with each other wherever possible"*.

## Built

- `src/dockreport.cpp` (plugin): while the left hand is docked (slide / pump / bolt, slide from the left, magazine, handle,
  drum, breech, or the front grip when two-handed), after the arm solve, the PALM (half way from L_Hand to L_MiddleF1) is
  measured against the PART: the zone's centre minus Tefa's own zones.json shift (new `zones::file_offset`), because a zone
  is moved to where the controller grabs comfortably (the LEMI's magazine zone sits 9 cm to its right), not to where the
  drawn hand belongs. One log line per hold, in the gun's axes (right / up / forward cm) plus the hand's turn, and
  `reframework/data/visceral_re8/dock_report.tsv` twice a second (opened shareable).
- `lua/visceral_re8_zones.lua`: zones_state.json now carries each zone's world centre.
- `tools/zone_sizes.py`: sizes each LG zone of the gun in hand as large as it can be without touching its neighbours (radii
  add up to the distance minus 1.5 cm, shared in proportion to today's sizes, 4-14 cm, growth at most 1.4x). The slide's
  two sides may overlap (one slide), and so may the F2's bolt and magazine (the code already lets the bolt win when a rack
  is due). A pump gun's shell port is sized with the rest.
- `tools/sim/dock_sweep.py`: per gun, walks the left controller into each zone, presses LG, reads the log line.

## Found `[verified-live 2026-11-04, simulator]`

- **The grabs do not all measure the same point.** The slide, the pump and the slide-from-the-left test the CONTROLLER
  (rack.cpp grab_point; the published "hand" point the spheres and the Grip Zones window use is the controller too); the
  magazine (reload.cpp grab_frame, since 2026-10-30 03:06) and the rifle's bolt test the DRAWN hand (the left IK target),
  which sits 10-15 cm from the controller. So a sphere can show the hand inside it while the grab, measuring the other
  point, says no. With the LEMI's magazine zone shrunk to 5.9 cm the controller at its centre left the drawn hand 10.3 cm
  away: no grab. This is why the zones cannot simply be shrunk until the two points agree. The question for Tefa: should
  every sphere follow the controller (your real hand) or the drawn hand?
- The hold on each part is a fixed pose in the gun's frame (the kept holds), so the numbers repeat exactly from hold to
  hold whatever the gun's angle: the LEMI slide, palm 6.5 cm from the slide joint (right +2.6, up +5.0, back 3.2); from the
  left 9.7 cm (right +6.6, up +4.5, back 5.4); the LEMI and F2 magazine holds have the SAME turn (yaw 163 pitch -47 roll
  -92): one shared magazine hold, not per gun; the F2: magazine 14.3 cm (forward 12.6), front grip 16.2 cm (back 15.9).
  Whether these are right needs a look: the simulator camera could not get a side view (the body follows the head and
  hides the gun), so no correction was applied blind.
- The distances between zones (centres): LEMI magazine-slide 14.4 cm, slide-slide-left 4.8; W870 pump-shell port 16.7;
  M1897 pump-port 24.2; F2 bolt-magazine 9.0, grip 29-30 cm from both.

## Zone sizes left installed (zones.json, backups beside it)

Only the zones that GREW were kept, so nothing gets harder to grab tonight: M1897 pump 9.8 → 13.3 cm, its shell port 6.9 →
9.4; F2 bolt 9 → 12.6, front grip 10 → 11.7. The shrinks (LEMI magazine 12 → 5.9, slide 14.1 → 7.0, slide-left 14 → 8.8;
W870 pump 14 → 7.1, port 16 → 8.1) were put back to Tefa's sizes until the measuring point is one point.

## Next

1. Tefa decides which point the spheres follow; then one point for every grab (rack.cpp, reload.cpp), and zone_sizes.py
   can shrink the overlapping ones safely.
2. A side view for the hold check: a camera that does not move the body (or Tefa's eyes); then dock_poses.json from the
   numbers.
3. The other twelve guns (not in this save): give them on the modding save and run the same.
