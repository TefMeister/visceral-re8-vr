# 2026-11-12: the torch you hold (Village b116)

Same design as RE2 / RE3 (`visceral-re2-vr/modding-notes/2026-11-12-six-holster-spots-and-the-torch-in-the-hand.md`, Tefa's
words there). Developer PC, Opus, simulator.

## How Village's is built

- Village's light is the game's HandLight: `app.PlayerHandLight` on the player, a `HandLight` scene object with the IES light
  and `app.HandLightPowerController`, plus `HandLightShaftLight`. Andyalpa's `re8_vr_holster.lua` (FLASH) already powers it
  (IsContinuousOn, IsLightOn, the controller's power) and aims it from the head at LockScene. Our plugin cannot find scene
  objects by name, so the plugin DECIDES and the script MOVES:
- `src/torch.cpp`: the left shoulder spot (RE2's numbers, 20 cm reach, 26 cm to leave), LG tap = out / back, LT = light (in
  the hand anywhere, not with LG held, not during a reload; in the spot), the grip by the controller (the lens at whichever end
  of the fist points forward, 0.25 hysteresis), the beam 8 cm out of the drawn fist (praydog's hand offset applied). Bridge
  244 state, 245-247 beam position, 248-251 beam turn (world; -Z shines).
- `visceral_re8_bridge.lua` turns those into `__visceral_torch`; `re8_vr_holster.lua` FLASH: with it, the head zone steps aside,
  the power follows LT, and in the hand the beam goes where the plugin says; in the spot the old head beam stays.
- `handstate.cpp`: the grip veto also while the torch is in the hand on a LONG gun (Tefa: "long weapons cannot be two handed").
- `re8_vr.lua`: no block while the torch is in the hand (block is both arms up + LT; LT is the light then). Tefa to confirm.

## Simulator `[verified-live 2026-11-12, simulator, n=1]`

Out, LT on: `__visceral_torch` hand=true light=true beam_ok=true; the HandLight's position = the plugin's beam position to
the centimetre; IES enabled. Overhand: "OVERHAND ... -0.77" with the fist tipped 140 degrees; back to ordinary at 1.00. Put back
with the light on: the head beam again. Daylight, so the beam itself was not judged by eye. No torch model yet (Blender).
