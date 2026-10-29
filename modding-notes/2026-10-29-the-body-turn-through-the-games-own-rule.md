# 2026-10-29 (afternoon) — the body turn through the game's own rule (home PC, Fable, flat desk run)

## The job
Tefa: *"please work on Ethan's body to turn like it does more naturally in RE2, we did get that sort of working already
but it broke a ton of things, let me know if this is something you need me in the headset for"*.

## What broke before, and why the lever was wrong
`body.cpp` (10-24/25) turned the DRAWN joints: the root alone never drew; all joints drew but the arms hung off turned
shoulders and the body swung into the view. The camera chain in VR, read in REFramework's own code today:
praydog's `re8_vr.lua` writes the camera controller's `<Rotation>` = the HEADSET's flattened yaw every frame and recentres
the view; `RE8VR::fix_player_camera` (C++) then writes the camera transform and joint from that plus the HMD. The game's
first-person player code aligns the BODY (the transform) to the camera controller's yaw with its own rule, so the body is
"one chunk with the head" because the game's rule sees the head as the camera. Turning the camera controller's yaw
instead would turn the VIEW (the render joint is built from it) [inferred-static 2026-10-29].

## The game's own rule (read live, REFramework MCP + the plugin)
`app.PlayerMovement` (the player's movement part; Ethan's is a per-character subclass): `updateAngle()`,
`calcAngleDiff()`, `destinationAngle()`, `get_CameraRotation()`, `getTurnSpeed(...)`, `processTurn(...)` (the turn-in-place
animation), `get_IsTurnCommandAcceptable()`, `tryQuickTurn()`; STATIC fields `TurnStartThreshold`, `AutoTurnStartThreshold`,
`AutoTurnSec`, `TurnAccelSec`, `MaxAngleDiff`; instance `AngleFollowRate`. Values as shipped `[verified-live 2026-10-29]`:
**TurnStartThreshold 45, AutoTurnStartThreshold 0.5, AutoTurnSec 5.0, TurnAccelSec 1.0, MaxAngleDiff 80.**
(The `calculateBodyDirection` / `set_bodyDirectionTarget` / `BodyRotateSpeedBase` names from the exe belong to no
Player/Character/Camera type; the probe found only `get_isTPSMode` on the TPS cameras. Left alone.)

## What was built: `turn.cpp` (visceral_re8_native, installed)
- Behind the same menu tick box as before ("Body turns like RE2", `S_BODY_TURN`): while on, the five statics are
  written every frame for the state of the moment: deadzone (TurnStartThreshold = AutoTurnStartThreshold) 60 standing,
  45 walking, 30 running (the game's `get_isMove` / `get_isSprint`), `AutoTurnSec` 1.2, `TurnAccelSec` 0.4 (guesses; the
  game's own 5.0 / 1.0 are logged). The originals are put back when the box is unticked. Nothing touches the view, the
  transform or any joint; `body.cpp`'s joint rewriting stays off while this runs.
- One log line a second: mode, deadzone, the threshold read back, body yaw, the game's camera yaw and their difference.
- Proved flat `[verified-live 2026-10-29, n=1 run]`: the statics read, the write holds (`threshold reads 60.0`), no
  crash, walking untouched. NOT proved: the body actually lagging the head (flat has no head; synthetic mouse input does
  not reach the game, so the camera could not be swung from the desk), the turn's speed, whether `AutoTurnStartThreshold`
  is degrees or a cosine (0.5 as shipped reads like cos 60; if the body never turns, try 0.5 there and leave only
  TurnStartThreshold in degrees).
- The first flat run found no `app.PlayerMovement` component by the base name; the lookup now tries the per-character
  subclasses (Pl1001 Ethan, Pl2001 Chris, Pl3000, Pl4000, Pl6000) and logs which matched: unseen.

## Driving facts
- Started by its exe with `XR_RUNTIME_JSON` (the OpenXR Simulator) + `SteamAppId`, Village hung before its title (VR
  textures set up, the log stopped, WM_CLOSE and `via.Application.exit` ignored): ended by the OS, the only time today
  the graceful quit was impossible. Through Steam, flat, it boots; the boot helper's "load most recent" template is hidden
  by the new Emporium window (REFramework's overlay is open at boot), so after its timeout: Up, F, wait, F, Insert.
- The Emporium options window is drawn in the game and reads right (screenshot sent to Tefa).

## What needs Tefa
The feel. In the headset with the box ticked: stand still and look 70 degrees left: does the body come round smoothly
after the 60-degree mark, and do the hands stay on the controllers? Walk and look 50 degrees: the same at 45? If the body
never turns, the `AutoTurnStartThreshold` unit is the first suspect (the note above). If it turns but too fast or slow,
`TURN_SEC` / `TURN_ACCEL_SEC` in settings.h.
