# Ethan's body turns like Leon's: one answer replaced (2026-11-10, Fable, home PC, OpenXR Simulator + VR Bench)

Tefa: *"ethan's body to be able to move it like Leon's body is rotating naturally, i did get to feel it once, you made
it work but it broke everything else around it, hands and aiming went all wrong because of it"*. Rule (2026-10-25):
the body comes round once the head is more than 60 degrees off standing, 45 walking, 30 running.

## Found, with the new live question line (below)

- Why the body is one chunk with the head: the loader (`RE8VR::fix_player_camera`, native; the Lua copy in re8_vr.lua
  is dead code behind `if true`) hands the head's direction to the game as its camera every frame, and
  `app.PlayerMovement.destinationAngle()` returns that yaw: the body is pointed at it at once. Head turned 70 degrees:
  player yaw -59.7 -> 10.3, `calcAngleDiff()` 0. `[measured 2026-11-10, simulator, n=2]`
- The 10-29 thresholds (`TurnStartThreshold` ...) are not consulted by this first-person body: `updateAngle` and
  `processTurn` were never called in 300 frames. `[measured]` turn.cpp cannot work. `[disproved]`
- **The lever:** a post-hook on `destinationAngle()` returning our own yaw (degrees, the camera controller's measure):
  the body takes it, legs and all. Held at the old yaw with the head 40 degrees aside: body -59.7, camera 160.3.
  `[verified-live 2026-11-10, simulator]`
- A first design kept the body's direction in the camera controller and the head's turn in the VR view offset. It
  held the view but the body still followed the head (the body reads `get_CameraRotation`, not the controller), and
  it touched the view. Dropped.

## Built: `lua/visceral_re8_bodyturn.lua` + four lines in `re8_vr.lua`

`re8_vr.lua` calls `VISCERAL_BODY_TURN.after()` right after the loader's camera fix. It keeps the body's yaw: starts
at the head's; any change of the view the headset did not make (the stick, a re-centre) is carried over whole;
otherwise it stays until the head is past the deadzone (60 / 45 / 30 by the player's own speed), then eases round
(140 deg/s + 2.5 per degree to go, ends within 1 degree). The hook hands that yaw to the game. Nothing else is
touched: no camera, no view offset, no joint; the arms are solved afterwards from wherever the shoulders are to the
same hand targets. Walking still goes where the head looks.

On by default; switch: VR Options Emporium > Comfort > "Body turns like Leon's" (saved in
`reframework/data/visceral_re8/bodyturn.json`, with the numbers).

## Proved on the simulator `[verified-live 2026-11-10, n=1 each]`

| done | body | view |
| --- | --- | --- |
| head 40 aside, standing | stays (-59.7) | 160.3 (turned 40) |
| head 70 aside | comes round to the head | unchanged by the turn |
| right stick turn (60 degrees) | turns with it at once | turned 60 |
| head 53 aside, standing | stays | |
| then walk forward | comes round (the 45 rule) | unchanged |

**Not worn.** For Tefa's eyes: looking 40 degrees over a shoulder with the hands out front, the upper arm and
shoulder fill the lower half of the picture (one simulator screenshot); whether that reads as natural or as too
much body is the feel question. If too much: smaller deadzones in bodyturn.json.

## The live question line (Tefa 2026-11-09: "install the connector so you can see stuff in real time")

`tools/sim/zz_visceral_eval.lua` (in the game's autorun, dev only) + `tools/sim/rv.py "<lua>"`: a Lua chunk goes in
through a file, runs on the game thread, the answer comes back, no restart. Helpers for singletons, fields, methods,
components; a table `E` that stays between questions (hooks installed from a question keep running). Everything in
this note was found with it in about half an hour. praydog's connector still cannot run on this REFramework build.
