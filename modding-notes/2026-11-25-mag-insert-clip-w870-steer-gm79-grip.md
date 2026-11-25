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

## b169: the GM 79's insert point rides the barrel (robot, the desk headset, the same afternoon)

- Measured (`tools/sim/q_gm79_insert.lua`, barrel fully open): the point (right wrist + a guessed 0/5/12 cm, `INSERT_OFF`) sat
  3.8 cm right of the gun's centre line, 4.7 cm under and 8.2 cm behind the chamber end (`vfx_muzzle2`, under `Carrier`), and
  stood still while the barrel swung. `breech.cpp measure_mouth` works it out after the arm solve (Body joint + the barrel's
  turn + the chamber end, kept in the right hand target's frame); shut: `BREAK_TOP_OFF` on top of the barrel's rear; open: the
  chamber end. After: 0.0 right; shut 5.3 up 11.1 fwd; open 10.0 up 12.2 fwd = the chamber end `[verified-live 2026-11-25, robot, n=1]`.
- LG + LT at the open barrel's top only said "the barrel is empty": LT loads there now only with something to load or take out.
- Robot `[verified-live 2026-11-25, robot, n=1 each]`: GM 79 front grip taken (b168 grip script); opens (70% with a 6 cm pull)
  and shuts from below; top hold opens it (let go at 80%: falls open) and shuts it; W870 pump grip taken, the gun's pitch
  -0.095 -> +0.102 with the left hand 10 cm up and back; LEMI fresh magazine logs "stays in the hand while the hand glides".
- Robot set-up notes: `drive_real_slot.sh` stops `keep.py` (restart it after every launch, or the robot's buttons do nothing);
  Village was on Single Frame Multipass (=2, desktop frozen): switched to =1 for the robot and back to =2 after; the first launch
  hung on "Checking for additional content" (picture only: the game ran at 72 fps behind the frozen window).

## Not established

- **The top hold sits behind the hinge** (on the barrel's rear, near the latch): pushing DOWN there opens it, the way the mod's
  drive works everywhere (the hand's way down = open). A hand on top AHEAD of the hinge (over the barrel) would be the
  physical push; that needs a dock of its own beside the insert point. Ask Tefa where the top hold should be.
- The top hold has no posed hand yet (b153 notes).
- Nothing of b168 / b169 worn by Tefa yet; how the magazine carry LOOKS is for the headset.

## b170: the top hold ahead of the hinge, no barrel from the front grip, the spent shell pulled out (the same afternoon)

Tefa: the top hold *"further forward please"*; *"please delete the part where i can grab and open the barrel from the front part,
i think it will surely interfere with the reloads"*; the spent shell pulled out by hand, the live one in after, the spent one kept
until LG (quoted in breech.cpp and settings.h).
- One dock, two places on the barrel: on top ahead of the hinge (6.1 up, 26 fwd at rest; Hand Poser spot 23 "top of the barrel")
  for opening and shutting, the chamber end only at a fully open barrel with a live one in the hand or a case to take out. The
  front grip is a two-handed hold only (`BREAK_FRONT_GRIP_MOVES false`).
- LT at the chamber end on a spent case: thumb and finger on it (spot 24), the hand pulls it 10 cm out along the barrel. With a
  live one in the hand the hand then carries that one back in (0.35 s, spot 25), it goes in, the spent one stays in the hand
  until LG. With an empty hand the hand leaves with it (spot 26); LG let go throws it.
- Robot `[verified-live 2026-11-25, robot, n=1 each]`: front grip LG + LT moves nothing; top hold opens and shuts; both pulls
  worked by the log (loaded 0 -> 1 after the push); the spent case seen in the palm in the empty-hand case.
- **Not working yet:** with a live one in the hand, the spent case is drawn by the second-shell copy, and the copy shows nothing
  for the GM 79 (part 0, and a scan of parts 0-80 in place, `tools/sim/partscan.py`, found none). So in that case the spent
  case is invisible while it is pulled and held. Next: find the grenade's mesh part another way (the gun's part list per joint,
  or the W870 way: one part on at a time with the gun's body away, flat), or draw it another way.
- Robot lessons: my robot runs brought the game window to the front again and again (keys.py, shot.py): that took Tefa's PC away
  while it ran (FAULTS row 2026-11-25, memory "work in the background").
