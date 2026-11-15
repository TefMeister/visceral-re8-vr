# 2026-11-15 (/lm, Opus, OpenXR Simulator + VR Bench, nobody in the headset): the second shotgun shell; b133 live

Tefa: *"go"* (game sessions on my own). Installed: b133 (the knife spot off, the right stick click no longer reaching
the game; b120's second shell under the gun inside it). Driven by `tools/sim/drive.sh` (VR Bench on, the save, in play
in the village), the W870 by quick-slot key 1.

- **The second shell's copy hangs under the gun:** `two_in_hand_test.py shotgun` took two rounds from the pouch ("2
  round(s) in the left hand"), the shell module made the copy ("copy made for gun 3021 (part 50) ... body joint found")
  and drew it ("the second shell is drawn beside the first"), and the one line that marks a failure, "the copy could NOT
  be hung under the gun", did not appear `[verified-live 2026-11-15, simulator, n=1]`. The test's search for the shell
  port did not dock this time (no LT presses), and the simulator's preview does not show the VR Bench hands, so whether
  both shells sit in the palm is still Tefa's look.
- **b133's knife spot is off in the running game:** the holster script's published slot state reads `knife = false`,
  and the saved settings file holds `knife_enabled false` `[verified-live 2026-11-15, simulator, n=1]`. The right stick
  click was not pressed (nothing in the log marks a crouch).
- **The ammo counter rows:** the older "zero until a shot" row is the same fault as the newer "does not update on an
  insert" row (Fable, no more blind refreshes): not touched.
- Closed by the game's own window (`close_village.py`, 11 s); VR Bench off.

## b134: the menu button (later the same session)

The Quest menu button: tap = the map, held 0.3 s = pause (the bindings send the left menu click to the unused `heal` action; `re8_vr.lua` reads it; the scope mod's left-menu fix only swallows the pause signal while Visceral owns the button). Simulator + VR Bench: tap opened the map, tap closed it, a 0.6 s hold opened the pause menu and it stayed open `[verified-live 2026-11-15, simulator, n=1 each]`. The first try paused twice on a hold (the scope fix and ours): cured by the owner switch. Not known: whether Virtual Desktop passes a single tap of the left menu button (a 2026-09-27 note says it claims double presses and holds).
