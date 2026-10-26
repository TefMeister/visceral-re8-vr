# Gold Digger: what 107 Ghost Hand runs on Village say together

From: `/gd`, 2026-10-26 (shelf `hands`, all 107 `begone-ghost-hand` reports, 2026-10-19 to 2026-10-25, home PC wears).
This project had no `engine-research/` folder yet; this inbox is the first thing in it.

## 1. The gestures mostly work `[measured 2026-10-19..25, n=107 runs]`

| gesture | finished |
| --- | --- |
| slide | 40 of 40 |
| breech | 24 of 24 |
| pump | 153 of 155 |
| shell | 121 of 124 |
| mag | 212 of 228 |
| bolt | 98 of 127 |

## 2. The bolt is never judged: the mod does not say how far it needs

17 bolt misses read *"not judged: the mod does not log how far it needs (`gh.value('<g>_need', metres)`)"*. The
other gestures log their `_need`; the bolt does not, so Ghost Hand cannot tell a short pull from a good one.
Proposed row: `[PD] log bolt_need (metres) in the Ghost Hand recorder like the other gestures` `MODEL: SONNET`.

## 3. The mag pull is sometimes measured short by the mod

Seven runs (2026-10-24 13:58; 2026-10-25 03:22, 09:47, 14:33, 15:50, 21:50, 21:54) have a mag miss where the
controllers moved **17-56 cm apart, more than the 16 cm needed, but the mod's own measure stayed under**. The real
hands did the pull; the mod's distance did not see it. One example (03:22): *"#47 mag at 122.898 s: the hands moved
22.0 cm apart, enough for the 16.0 cm needed, but the mod measured less"*. Worth checking which two points the mod
measures between (hand to magazine well, or hand to where the grab started) against the controller distance.
`[measured, n=7 misses]`

## 4. In 16 runs the game's hands were logged about 156 m away: the recorder mixed up spaces

16 of 107 reports have the game hand "wandering" 156.3-157.3 m (always the same ~15,650 cm), and 13 of those also
show the lag stuck at 11-12 frames, which is Ghost Hand's search limit, not a real lag. In the worst (2026-10-24
23:10, 40 s), the **usual** gap itself is 156 m and the game hand "jumped" 3,601 times, i.e. on nearly every frame.
That is the game hand written in world coordinates (the player's place in the level) while the controller is in room
coordinates: for part or all of those runs the recorder's room-space step was not applied (likely before the camera
was found, in a menu or a load). These runs say nothing about the hands; ignore their jump and lag numbers.
Proposed row: `[PD] Ghost Hand recorder: skip (or mark) a frame when the room-space step has no camera, instead of
logging the world position` `MODEL: OPUS`. Lesson for the Ghost Hand checker filed with BeG0nE the same day.

## 5. Calm-hand jumps

Apart from the 156 m runs, "game hand jumped while the controller was calm" ranges from 1 to 812 per run (812 on
2026-10-24 23:38, 494 on 23:55). Most runs sit at 3-70. Not split by cause here; read the full report for a run
before acting on it.
