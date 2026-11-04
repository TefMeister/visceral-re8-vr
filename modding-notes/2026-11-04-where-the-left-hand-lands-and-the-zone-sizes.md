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

## Later the same night (2026-11-04 23:15 to 11-05 00:30): "real hand", the F2's magazine hold, the headset run

- Tefa: *"real hand please"*. Every grab now measures the controller: the magazine (reload.cpp grab_frame, hand_near_mag)
  and the rifle's bolt (rack.cpp grab_point) no longer measure the drawn hand. On the simulator the F2's magazine took at
  0.4 cm `[verified-live 2026-11-04, simulator, n=1]`. Then zone_sizes.py's sizes went in (LEMI magazine 5.9 / slide 7.0 /
  slide-left 8.8, W870 pump 7.1 / port 8.1, M1897 pump 13.3 / port 9.4, F2 bolt 14 / grip 12.8); the LEMI / W870 shrinks
  are not yet checked by a grab.
- Tefa: the F2's LG on the magazine landed the hand *"on that grip handle"* (the right hand's trigger handle) instead, but
  after taking the magazine out and putting it back, *"it lands on the right spot then"*. ⚠️ The magazine's anchor is NOT
  on the magazine (Tefa saw "0 cm from the magazine" by my yardstick as the hand by the trigger handle), so the yardstick
  for a magazine is the re-insert hold, not the anchor. tools/sim/mag_match.py: press (A), out, in with LG held (B), shift
  dock spot 4 by B - A, press again. F2: A 13.9 cm, B 21.9, after the shift both 21.6 `[verified-live 2026-11-04,
  simulator]`; in the headset Tefa: "hand is closest to the mag" `[verified-live 2026-11-05, headset, n=1]`. WCX / Dragoon /
  SYG-12 NOT done: the gun went invisible while the test held / pulled the magazine (Tefa watching), became visible when
  the virtual grip and trigger were let go. Suspect: the magazine-hiding (hide_mag_part / setPartsEnable with magazine part
  -1) hides more than the magazine on those guns `[hypothesis]`.
- Headset run 00:15-00:25 (Tefa), what was said: GOOD: the F2's magazine hold near the magazine. FAULTS: (1) at the shell
  port with shells in hand the fingers did not move at all: Hand Poser (its "rounds from the pouch" pose) writes the held
  fingers at LateUpdateBehavior and PrepareRendering over the clip; fixed: the plugin says in bridge slot 186 which hand a
  clip plays on and hand_poser.lua lets go of that hand meanwhile (the clip itself turns the index 42 deg, the thumb 30, so
  it is visible) `[compile-verified]`; (2) one LT put both shells in: now one shell per LT press (shells.cpp); (3) the hand
  did not open at the magazine zone: fingers.cpp now opens in it too; (4) "a flickering rifle in my left hand while i'm
  holding the pistol ... after i swapped from a rifle to handgun ... the rifle was turned backwards riding my left hand",
  constant for a while: NOT FOUND in the log. Leads: right after the swap (00:16:07) the grip script logs "the ANIMATION
  has moved the socket 155-162 deg under the held grip" while LG holds the pistol two-handed: the game's own put-away of
  the rifle may be playing on the left hand (Village puts the old gun away with the left hand) and our hand placement and
  the game's alternate frame by frame `[hypothesis]`; (5) the rifle's first shot came late after RT: not looked at yet.
  The run's log is kept (logs/visceral-re8-vr/re2_framework_log-2026-11-05-0015-headset-flicker.txt in the work folder).
- ⚠️ The BeG0nE rider died again at 22:46 on the same locked Ghost Hand file, so the headset run was NOT collected (no
  report, no recording). Restarted 00:2x. The fix waits for the Lanes test to finish (lanes-next is frozen).
- Two Hand Poser pose files are empty (the M1897 "@ slide from the left", the F2 "@ right hand on the bolt"): JSON errors
  in the log; the shell port is spot 8, the same number as "slide from the left", so Hand Poser names the shell-port pose
  "slide from the left" (pairs.cpp DOCKS shell port 8.0f) `[inferred-static]`.
