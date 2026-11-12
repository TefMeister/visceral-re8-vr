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
