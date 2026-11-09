# The free left hand was drawn from an old controller reading (2026-11-10, Fable, home PC, OpenXR Simulator + VR Bench)

Tefa 2026-11-09: *"left hand is still jittery when on it's own"*. Ghost Hand the same night: the left hand wandered
7.6 cm from its usual place, the right 0.6 cm.

## What was found

- `smooth.cpp`'s "the game docked the free hand: put back on the controller" fired 65,905 times in one 17-minute worn
  run, about once a frame, although the game's dock was already off (`nodock`). `[measured 2026-11-09 log]`
- A probe built into the plugin (`freehand probe` log lines, every 2 s) measures, per arm solve of a frame, how far the
  left target praydog wrote is from our prediction (the frame-start snapshot of the controller and camera):
  solve 1, 3 and later: 0.0 mm with the hand still, 4-5 mm mean and 11-27 mm max (one 107 mm) with the hand swung at
  12-25 mm a frame; **solve 2: 18-73 cm off, every frame**. `[measured 2026-11-10, simulator, n=2 runs]`
- So nothing docked (praydog's `was_gripping_weapon` flag: 0 frames). Solve 2's target is far off for both hands and the
  next solve puts it right; the old code took solve 2 for a dock, put the hand on the snapshot prediction, and then held
  that for the rest of the frame, over praydog's fresh last solve. The drawn left hand was therefore always the
  snapshot: up to 1.5 cm (in spikes more) behind the pose the right hand and the picture use, by an amount that changes
  every frame. That is the stepped motion. `[inferred-static]` from the code path plus the numbers above.

## The fix

`FREE_PUTBACK_MODE = 1` (settings.h): the free hand is put back only when praydog's own flag says he docked; otherwise
his placement is drawn, exactly as the right hand's is. `reframework/data/visceral_re8/freehand.json {"mode": 0}`
brings the old behaviour back live for a comparison. Put-backs with the fix: 0 of ~300 frames per run.
`[verified-live 2026-11-10, simulator, n=2]`. **Not worn yet**: the headset check is Ghost Hand's left "wanders" number
coming down to the right hand's.

## Left open

- What solve 2 is (the game's own IK pass, or praydog's with a camera not yet set) is not pinned down; it is harmless
  as long as a later solve follows, which the probe shows every frame.
- With a real dock (no gun, or the grip script asking), the flag is one frame old: the hand may show one docked frame
  before the put-back. Not seen; watch for a flicker near the grip.
- `nodock` logs "0 asks answered" at switch-on only; whether it fakes anything later is not shown by the log.
- Tool: `dev-archive/native/tools/sim/hand_swing.py` (a smooth swing of the left controller through VR Bench).
