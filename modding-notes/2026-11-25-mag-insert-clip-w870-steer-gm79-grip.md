# 2026-11-25 afternoon (Build PC, Opus): the magazine-insert clip read frame by frame; W870 steering; GM 79 front grip (b168)

## What Tefa asked (word for word)

- Clip `mag insert hand jitter RE8.mp4` (D:\Capcut export, 7 s, 60 fps, b164 worn): *"analyze this video frame by frame and see if
  anything can be done to smooth out the hand's jumping between some parts and the hand to follow the mag so it looks like there
  is alway shand contact with the mag when being inserted"*.
- Then: *"the shell insert point is off to the right by quite a bit, LG doesn't dock on the front part of the launcher and it seems
  that the docking points have to be added for holding the launcher from the top to break it open after B, holding it from the
  bottom like normal to two-hand it. also holding it from the bottom and top of the barrel and having LG and LT to be able to bend
  it closed again. W870 TAC is is only steered with the right hand, when LG is docked on the weapon it just rides along and
  doesn't steer it."*

## The clip, frame by frame `[measured 2026-11-25, every frame tiled and brightened]`

Three inserts of the LEMI's fresh magazine (log 12:31:06-12:31:31: eight inserts, each pulled back out of the bottom, the last seated).
- **The jump:** frames 189->190 and 339->340: the magazine leaves the hand in ONE frame and appears half way into the grip, 12-14 cm
  away (log "smooth: ... gap 0.117-0.138 m"). The hand stays behind, fingers open and empty, and glides after it for ~7 frames;
  196->197 / 346->347 it lands under the magazine and the fingers close in one frame. 2-3 frames of small settling follow.
- Once on, the hand rides with the magazine in and back out: fine.
- The video repeats every fifth frame (frame-difference 0.02-0.04 at 16, 21, 26 ...): the recorder, not the mod.

## Causes and b168

- `reload.cpp` rail_enter (the fresh-magazine and LT-at-the-well paths) put the magazine at the bottom of the grip's line at once
  and started its travel up, while `smooth.cpp` eased the hand there over 0.15 s. Now (`RAIL_CARRY_ON`) the magazine waits
  `RAIL_CARRY_SEC` (0.17 s) at the bottom, drawn in the gliding hand and eased onto the grip's bottom by the glide's progress
  (`reload_pose.cpp`, `rail_carry()`), then travels up as before. `[compile-verified 2026-11-25]`
- The LEMI's magazine-OUT finger clip (b160) was followed going IN too, from "96% out" (log 12:31:09.214 "follows the pull (now 96%
  out)") = the open hand of the pull's end. Only a pull follows it now (`INSERT_NO_PULL_CLIP`, `g_rail_in`). `[compile-verified]`
- W870: the grip script (`re8_vrz_begone_grip.lua`) returned before reading the plugin's "hand on the pump" flag (slot 99) when the
  gun had no frozen grip spot and praydog did not dock, which is always the W870 (log 12:23:49-52: 3 s on the pump, no "grip
  taken"); the M1897 had a spot and steered (12:46:37, 13:01:05-31). Slot 99 now keeps the pass going. `[luac -p ok]`
- GM 79: the long-gun rule (no grip within 25 cm of the right hand) refused its kept front grip, 15.3 cm out (log 12:33:30-39: LG
  pressed 0.4-17 cm from the spot, `our_grip=false` every time). Its own minimum 8 cm (`LONG_GRIP_MIN_BY_GUN`). `[luac -p ok]`

## Not established

- **The GM 79's insert point "off to the right":** the point is the right wrist (IK target) + (0, 5, 12 cm) in the gun's turn, a
  first guess (settings.h `INSERT_OFF`), never measured against the breech. The dock report only measures the palm against that
  same point (palm 3.2-4.0 cm to its left, `dock_report.tsv`), so it cannot say where the breech is. Needs the game running:
  the `Carrier` / `Ammo01` joints' drawn place against the zone's centre. The top hold (to break it open after B, and to push it
  shut) IS that point (pairs.cpp, spot 7, offered only with the latch open), so it moves with the fix.
- The top hold has no posed hand yet (b153 notes).
- None of b168 has been worn.
