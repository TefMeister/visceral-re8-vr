# 2026-11-12: the camera taken by the game at examine spots (Beneviento house, the Mia mannequin, save 5)

Tefa: *"the camera being grabbed from the player in certain places, not all of them universally the same ... the wooden
Mia mannequin, when interacted with the various spots on it, the camera grabs control and this part is especially bad in
VR, can you see if this part of the game can leave the camera control entirely to the player. these spots need to be
looked at to trigger the interaction prompt. it's save nr 5"*. Developer PC, Opus, Tefa playing FLAT, read live through
`tools/sim/rv.py` (the eval script), nothing written to disk.

## What app.PlayerCamera does at the start of an examine `[verified-live 2026-11-12, flat, n=1]`

At the press (t = 0): `isReceptionControll` true -> false (the player's camera input off), `isUseNextEventReferenceLerp`
false -> true, `toElasticRotationTransSec` -1 -> 0.75 (an "elastic" turn toward the event's reference, 0.75 s). At t = 0.3 s:
`isReceptionControll` back true, `IsOldSetExternalTask` false -> true (an outside task now drives it), `IsOldStandOrCrouch`
true -> false; then every frame `controlRate` / `OldControlRate` ramp 0 -> 1, `upperBodyTransformRate` 1 -> down,
`nearClipTransRate` up, and `CurrentXRotateUpperLimit`, `CurrentXRotateLowerLimit`, `CurrentControlledAngleLRLimit` halve
each frame toward 0 (the look is clamped around the target). The watcher's notebook filled at 0.55 s, so the end of the
examine and any switch of the primary camera were not seen. `PlayerCamera` is not on the main camera's game object.

## Two live tests, both NO (Tefa: "still grabs the camera", "all same") `[verified-live 2026-11-12, flat, n=1 each]`

1. `controlRate` forced to 0 after `updateControlRate` and `isUseNextEventReferenceLerp` forced false before `lateUpdate`
   (both hooks fired, 1,990 times): still grabbed.
2. `updateEventLimit`, `updateLimitParam` and `startElasticRotationForCounter` skipped (383 skips each in 2 s, every
   frame): still grabbed; normal look and crouch unaffected.
Both switched off again (flags in the eval script's E table); a game restart removes the hooks.

## So the turn comes from somewhere else

Not the control-rate blend, not the limit clamp. Candidates for the next round (`MODEL: FABLE`: engine behaviour nobody
wrote down, two tries resisted): the outside task itself (what `IsOldSetExternalTask` names: find the setter and the
task's type), the camera driven by the player's animation (`IsControlledByAnimation`, the head joint while Ethan's examine
animation plays), the primary camera switching to another camera object, or the interact manager's own look-at (re8_vr.lua
already wraps `app.InteractManager` lateUpdate for VR). First step next time: a watcher with a bigger, filtered notebook
over the WHOLE examine (start to end), plus the primary camera's object and the PlayerCamera's final rotation every frame;
then the same in the pretend headset.

## Solved flat, built for VR (same day, Fable)

- A watcher over a whole examine: for its whole length (6-8 s) `get_IsControlledByHalfAnimation` and
  `checkEventCameraType` are true, `IsOldSetExternalTask` true, `controlRate` 1; no setter is called (fields written
  directly) and the primary camera stays MainCamera. Test 3 (those getters forced false, input forced on; hooks fired
  2,569 times): still grabbed `[verified-live, n=1]`: the internals do not go through the getters.
- Measured angles: the camera's turn = `_CameraJoint` (a camera bone of Ethan's animation: round by ~60 degrees and 70
  down), the mouse allowed a few degrees on top; `OperatedCameraRot` / `DesiredCameraRot` sit frozen at a LEVEL direction
  (not the player's real look) `[measured]`.
- Test 4 (turn overwritten with `OperatedCameraRot` after lateUpdate): the override held all examine long, but the view
  jumped to that level direction. Test 5 (the real camera turn of the frame before it starts, held, `set_cameraRotation` +
  `setCameraTransformRotation` after lateUpdate): Tefa: *"nice i think it works! the camera followed head height and
  position, but didn't take control of it"* `[verified-live 2026-11-12, flat, n=1]`. What is drawn = what we set (the main
  camera joint, read at BeginRendering).
- VR: praydog's `on_post_player_camera_update` treats this as a cutscene (BaseTransSolver type not 0) and puts the headset
  on top of the swinging turn. Built into our `lua/re8_vr.lua`: while half-animation control lasts (and its 0.3 s lead-in
  and 0.2 s tail; never under full animation control) the turn it starts from is the level direction of the frame
  before; the place still follows the game. Option "Keep my view when Ethan examines something" (on). `luac -p` clean;
  NOT installed, NOT run (Tefa's flat game was running) `[compile-verified]`.
- Open: the way back at the end (flat: "when returning view it didn't go back to where it started from", in test 4);
  whether other half-animation moments (ladders, doors, pick-ups) feel right held; the place following Ethan's lean in VR.
