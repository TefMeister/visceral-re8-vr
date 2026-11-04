# Matching the scope's picture to the world by measuring: the first night (2026-11-04, 21:15-22:15)

Home PC, Fable, the OpenXR Simulator (no headset), VR Bench for the hands. Tefa's ask (2026-10-31): *"if all the adaptive
adjustments are off, how can the scope and game picture still differ? ... using all the tools and knowledge we have,
somehow match them up?"* Plan: measure the glass against the world behind it instead of judging by eye; set the scope's
trim and exposure from the measured ratio; Tefa judges only the end.

## What was built

- `dev-archive/native/tools/scope_measure.py`: `shot` (a full-size picture from the simulator through its
  screenshot_request.json), `find` (the glass by its dark ring; unreliable, give the centre by hand), `compare` (the mean
  colour inside the glass against a ring just outside it, a sector of the ring so the scope's own tube is never counted;
  in sRGB and in linear light; the per-channel world/scope ratio logged), `compare2` (the glass against a second picture
  with the rifle lowered, same head), `locate` (the glass's shrunk picture searched over the lowered picture), `fit`
  (across spots: one gain, or a gap that changes with brightness).
- `dev-archive/native/tools/sim/`: `village_sim_boot.py` (launch on the simulator + VR Bench: A, A, stick up, A, wait, A),
  `scope_aim_at.py`, `scope_pair.py`, `scope_walkshot.py`, `scope_lower.py` (the rifle poses, pictures, measurements).

## What was learned about driving it `[verified-live 2026-11-04, simulator]`

- The simulator's preview must be large for pictures (`settings.json` `window_width 2560, window_height 1400,
  full_render true`; it was 1152x201); the screenshot is the preview's size. Set it with no game running.
- ⚠️ A click that lands on the simulator's preview window puts it into mouse-look; with Village then warping the
  cursor, the head spins (yaw ran to -9000 deg, pitch pinned at 86) and `set_head_pose` cannot hold it. ESC by
  PostMessage does nothing; a real ESC into the focused preview stops the spin but the capture stays. The only clean way
  back was a game restart. So: NEVER click on any window while the preview exists (Menu-o-matiC clicks included); use
  keys to the focused game window, VR Bench buttons and the command files.
- The rifle in VR Bench's hands: **controller pitch 90 = the rifle level**; less points it UP (pitch 0 = about 45 up,
  pitch 50 or 70 still up), more points it down. With the right hand at (-0.07, 1.48, -0.10) m and the left at
  (-0.07, 1.55, -0.45), both pitch 90, head at (0, 1.70, 0) looking level, the scope glass sits at (380, 610) r 56 px in
  the left eye of a 1920x1033 picture and shows the magnified world. Two-handed (left squeeze) made no difference to the
  direction. Looking up or down: rotate the hand positions about the eye AND use controller pitch 90 - pitch; the first
  try used 90 + pitch (the sign is the other way) and my second try put the hands behind the head.
- The glass's picture is NOT what sits behind the glass on the screen line: the bore points elsewhere, and the glass
  content is 4x magnified; a comparison is valid only on a uniform surface that fills both the glass and the ring
  (a wall up close, snow at the feet, the overcast sky), or with the glass content found in the lowered picture.

## Numbers so far (all `[measured 2026-11-04, simulator, n=1 each]`, same-material spots only)

| spot | world/scope brightness (linear) | world/scope R, G, B | colour of the gap B/R |
| --- | --- | --- | --- |
| brick wall ahead (sc12, the ring = the same wall, open side) | 0.57 | 0.49, 0.65, 0.78 | 1.57 |
| same wall, first far look (sc11) | 0.73 | 0.61, 0.89, 1.25 | 2.04 |

Read: at that wall the scope is about 1.7x too bright and too red / too little blue. The other spots (snow path, sky,
spot1-4 pairs) compared different content and are not usable; `fit` over them is meaningless (slopes +3 / -1.4).

## The scope's recipe today (read from its status file and source)

Raw-HDR mirror source, GT curve on `exposure = exposure_gt (10846.8) * 0.4 * 2^-EV` with the WORLD's held EV 6.4
(ev_auto = 1, `ev=6.400 ev_ok=1`), `tone_wp = 1` (white point 5.6 / 5.6 = 1 outdoors), then the atmosphere white
balance `wb_amount = -1.5` x gate 1.0 outdoors (R x1.27, G x1.06, B x0.79: WARMER), then the colour table (cube), then
the hand trim r 0.86 g 1.0 b 1.3 (net with wb: R 1.09 G 1.06 B 1.03). So two knobs pull against each other and the net
is still slightly warm, which agrees with the wall measurement's direction.

## Next (one simulator session, then Tefa's look)

1. Uniform spots: walk the player up to the plaster wall (left stick, 3-4 s), the stone wall by the gate, the snow
   bank at eye level; and the sky / ground with the corrected aim script. Three or four spots, `compare`, `fit`.
2. If one gain fits: set `re_scope_trim.txt` r/g/b from the mean ratio (world/scope per channel) and `exposure_gt` from
   the brightness, with `wb_amount` 0 so one knob does the colour; re-measure; expect ratios near 1.0.
3. If the gap changes with brightness: the curve (GT contrast / white point) or the exposure, not a gain; measure at
   three brightness levels and fit the curve's input gain + contrast.
4. One headset look by Tefa, judging only the end.
