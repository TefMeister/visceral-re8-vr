# Gold Digger 2026-11-01: the new ammo-count call is rejected; three smaller log facts

From: `/gd` (inside `/fullscan`), reading 14 shelved REFramework logs (2026-10-27 to 11-01) and 66 Ghost Hand reports.

1. **`order.updateRemainAmmo(mode, item)` never runs: REFramework rejects it every time.**
   Log `2026-11-01_01-55-44_PC1_re2_framework_log.txt`: `[warning] Invalid number of arguments passed to
   REMethodDefinition::invoke for app.GUIRemainAmmoOrder.updateRemainAmmo`, 48 times; the very next line is the
   bridge's own `ammo counter: updateRemainAmmo through the order called`, so our log says "called" for a call that
   did not happen. Again 6 times on 11-01 09:18 (the `10-43-14` item) `[measured 2026-11-01, n=2 runs]`. This is the
   "Added (Lua only, installed, unworn)" ammo-counter row. Proposed: read the method's parameter count (the bridge's
   type probe lists it) and call it with that many; log the call's result, not that it was sent.
2. **The in-game Hand Poser script keeps finding `hand_poser\command.json` empty**: `[JSON] Failed to load ...
   unexpected end of input` 21,038 times in `2026-10-31_14-16-21`, 307 in `2026-11-01_01-55-44`, 82 in `10-31_23-32`
   `[measured 2026-10-31..11-01]`. The window writes it safely (temp file + replace, `HandPoser.cs` line 105), so either
   the file was left at 0 bytes with the window closed, or something else writes it `[hypothesis]`. Harmless, but it
   buries the log. Proposed: the script treats a missing or empty file as "no command" before calling
   `json.load_file` (an `io.open` size check), or looks once a second instead of every 3 frames while it is empty.
   `zones_open.json` / `zones.json` read empty too (38 and 156 lines); same fix.
3. `[visceral-re8-hud] app.GUIRequestOpenQuickEquipParameter: type not found` and `app.PlayerUpdater: type not found`
   in every run since 11-01 01:55 `[measured 2026-11-01, n=3 runs]`: whatever that HUD part does is not running.
4. Already fixed, for the record: the `via.gui.Text.set_FontSize` access violations (1,305 / 2,016 / 4,742 caught per
   run, 10-30 to 10-31 00:44) stop after the labels change; 0 since `[measured 2026-10-30..11-01]`.

Ghost Hand side (BeG0nE, not the mod): the magazine "misses" that read "the hands moved 49 cm apart, enough for the
16 cm needed, but the mod measured less" (7 reports, 10-30 to 11-01) are the wrong verdict the 2026-10-31 BeG0nE idea
predicted once `mag_need` is sent: a magazine must come WITHIN 16 cm, not move 16 cm apart. Not a mod fault; filed
with BeG0nE.
