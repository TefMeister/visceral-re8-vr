# 2026-11-26f: the glitchy legs are the game's own foot fitting; the cutscene "blip" at a stop; the body hold both ways

/ms, Build PC, Fable, Tefa in the headset all evening (about 19:56 to midnight). Rebuild 2, b189 plus tonight's
uncommitted-then-committed changes (no new build number yet: the prologue bundle b190 is saved only on Tefa's word).

## What Tefa asked for, in his words

- *"legs still glitchy, body still jumps ahead"*; *"still all glitchy. so next step - clean install?"*
- *"please just save this, as it is, all the game files and reframework files - and then we do a clean install of the
  game and same version of reframework"*; saves wiped too ("saves A").
- *"from now on we have to save parts of this mod as bundles that we know for sure are working. prologue first."*
- After the legs fix: *"it looks great, feet are like they are supposed to and on uneven ground this is the best to ask
  for"*.
- *"when stopping running, then hands do this second long animation that should not be there"*.
- *"can we just eliminate these animations as we did with re2, and use the same walking animation for everything ...
  and then we'll fine tune the cutscenes that break because of it - or does re8 really not work like this"*.
- Last run (23:12): *"hand flip gone almost, there is still a quick little flick after running and stopping"*.

## 1. The glitchy legs (RE8-091): the cause, and what it was NOT

- **Cause `[verified-live 2026-11-26, n=2 runs, Tefa's eyes]`:** `via.motion.IkLeg` (the game's leg fitting) with
  `EnabledGroundAdjust = true` (the game's default). On uneven ground a foot pops up about 8 cm in one picture and
  sinks back over the next four, the hip still. Set to `false`: clean legs, also on slopes. Flat floors (the prologue
  house) never showed it, which is why it looked new.
- **It is the stock game plus praydog's VR**, not our mod: seen on a TRUE reinstall (game deleted, saves wiped, all 28
  files of the fresh install byte-identical to the old ones) with stock REFramework nightly 01451 (22c713ce) AND the
  March build 76298bd, nothing of ours in. Tefa: *"i have just never noticed it"*.
- **Cleared on the way `[disproved 2026-11-26]`:** every part of our plugin (off.txt halving, all off), the script
  half, decoupled pitch, picture settings and VSync, broken game files, the REFramework version.
- **How it is held now:** a probe script, `dev-archive/rebuild2/lua/visceral_re8_legs_probe.lua`, sets the property
  every frame at UpdateMotion pre from `reframework/data/visceral_re8/legs.json` (`{"EnabledGroundAdjust": false}`).
  STILL TO DO: build it into the plugin as a part with an `off.txt` word, retire the probe.
- The other IkLeg values as the game set them are in the dossier (ray casts, damping, foot lock). Untried levers on the
  same component: `CenterRotationCtrl` / `CenterRotOffset`, `LeanMode` / `LeanCtrl` / `LeanAngle`.
- The 2026-11-25 "wipe" was NOT a true reinstall (the paks stayed, Steam only validated). The true one was tonight.
- `tools/walkread.py` is not to be trusted yet: its snap counter (40 mm a picture) counts plain running, and the
  motion-layer readout is junk (frame -0, end 0, id 1). The motion id readout must work before any RE2-style
  "one motion" work can start.

## 2. Why the body "jumped ahead" and the hands flipped at a running stop (RE8-092, RE8-096)

- **The loader's cutscene flag** (`re8vr.is_in_cutscene`) goes up whenever the camera's `currentType` is not 0 and
  stays up 1.0 s after (`RE8VR::fix_player_camera`, read at 22c713ce). **A running stop raises it with no event
  running** ("blip"): 13 blips in 13 stops in the 23:12 run `[measured]`.
- While it is up the loader (a) zeroes the IkLeg centre offset in `update_body_ik`, so the body goes back to its own
  animated spot: that was most of the "lean" at a stop; (b) lets the game's arm animation have the hands (the Lua
  layer's hand code returns early); (c) hides the body if `RE8VR_AutoHide*BodyCutscenes` is on, which is why the old
  install (hide on) never showed any of this.
- **The fix (`bodyplace.json` `"blip": 1`, bridge `B.camera_step`):** when the flag is up and no event runs and the
  arm is not jacked, the bridge puts the flag DOWN right after the loader's camera fix and leaves it down for the rest
  of the frame. The loader raises it again every frame, so it is decided anew each frame.
  - Tefa, 23:12 run: *"hand flip gone almost"* `[verified-live 2026-11-26, n=1 run, 13 stops]`.
  - The walk file of that run: at ten running stops the neck came at most 1.8 cm forward of standing and the lean
    fix asked for 0.0 cm `[measured, n=10 stops, one run; the stops were short]`. So the 12 cm "stop lean" measured
    earlier the same day was the loader's zeroing, not the motion. Root cause, not a patch on top.
- **A first try sat in dead code:** the Lua `fix_player_camera` body in `re8_vr.lua` after
  `if true then re8vr:fix_player_camera(player_camera) ... return end` never runs. The insert was removed; the file
  is byte-identical to b189's.
- **Still open, the "quick little flick":** the wrists do not move at a stop (under 0.5 cm a picture, hand within
  4 cm of the controller, all 13 stops) `[measured]`. So it is the hand's turn, the elbow, or the fingers. The walk
  file (format 2) now writes both elbows and both hands' turn as seen from the view; Tefa is asked what it looks like.
- Hand IK order, for whoever builds on it: `re8_vr.lua` calls `update_hand_ik` at UpdateMotion post,
  LateUpdateBehavior post and **PrepareRendering PRE**. Our joint writer runs at PrepareRendering POST. A spine
  written at post would drag the hands off the controllers (the arms hang off it); written before the pre call it
  might not `[hypothesis]`.

## 3. Which joints lean (RE8-097), from the 23:12 walk file (torso local turns, new columns)

Pitch against standing, degrees `[measured, one run]`:

| | Hip | Spine_0 | Spine_1 | Spine_2 | Neck_0 | neck vs standing |
| --- | --- | --- | --- | --- | --- | --- |
| running | +10..13 | +12..15 | -20..-24 | 0 (never moves) | +-3 | within 4 cm |
| event A, 32.5 s (hip dips to 0.46) | +8..11 | +22 | -30 | 0 | 8 | 19 cm forward, then 11 back |
| event B, 41 s (hip to 0.11, 45 deg of yaw/roll) | +36 | +34 | -64 | 0 | 5 | 39 cm forward, then 35 back |

- Hip and Spine_0 pitch forward and Spine_1 turns back by about the sum: the chest stays upright, the lower back
  folds. In the two events (the jump down with the slide, and the vault; which is which is not settled) **the
  body's PLACE against the eyes swings far more than any joint turns**. Holding spine joints would not fix what Tefa
  sees there; holding the place does.
- Event B: both game hands jump 15 and 21 cm against the controllers in ONE picture, 0.33 s after the stop: the
  vault-end "teleport" Tefa reports, seen by the recorder. Not explained yet.

## 4. The body hold, both ways (leanmath.h, built and installed 23:25, NOT WORN)

- Until now the lean fix took out only a forward lean and let go over 0.3 s. The events swing forward THEN back, so
  the back swing stayed whole and the late let-go added to it: a likely cause of *"the body does go back a bit too
  much"* at every strength tried (100, 60, 40 %) `[hypothesis]`.
- Now: a swing back past the 4 cm dead band is asked out too (a negative ask, the body sits further forward), the ask
  follows the measurement both ways (0.05 s out, 0.08 s back), limits 40 cm each way. `bodyplace.json`: `"lean"` is
  the strength (now 1.0), `"lean_back"` an optional separate strength for the back half. The bridge takes asks up to
  45 cm either sign. `[compile-verified; verified-numerically: leanreplay selftest, 14 checks incl. the swing back]`
- Honest scope: this is "one still body PLACE", not yet "one walking animation for everything". The RE2 way (rewritten
  motion lists, the running-stop hook) needs Village's motion ids first; Village's motion lists are another version.

## 5. Kept on this PC (not on GitHub)

- The whole old game folder as it stood, the fresh install's checksums, b189's five files, both REFramework builds:
  on D under "RE Village REFramework builds". Kept logs in `~/visceral-kept-logs/`, `re8-2026-11-26-*`.
- Tefa's clip `re8 body glitches.mp4` (D, "Capcut export"): frames 72-96 the view inside the jacket before the jump
  down, 162-192 inside the coat collar, from about 600 the hand flipping to a drooped pose for up to a second.

## 6. Installed now (game closed)

b189's files plus: `visceral_re8.dll` sha256 c821029f... (rec format 2, lean both ways), tonight's
`visceral_re8_bridge.lua`, the legs probe script, `legs.json` (ground adjust off), `bodyplace.json`
(`lean 1.0, blip 1`). REFramework nightly 01451. `re2_fw_config.txt` = b189's (body shown, decoupled pitch).

## 7. Rule Tefa set tonight

Known-working bundles per game section, prologue first: saved only after he has worn it and says it works, as the
next build number (b190 "prologue"), so a reinstall never costs a finished section again.
