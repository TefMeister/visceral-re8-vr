# The empty click: Village has none of its own (2026-11-01, Opus, simulator)

Tefa: "can you see about the empty click sounds next" (idea of 2026-10-31: the game's own empty click on every trigger pull).

## Measured `[verified-live 2026-11-01, simulator, n=1 each]` (tools/sim/hear.py records what the PC plays, WASAPI loopback)
- Our click (dryfire.cpp, sfx/dry_click.wav): about -14 dBFS for 80 ms on each press; three presses 0.6 s apart each clicked,
  none cut. Background about -35 to -45.
- `app.PlayerGun.requestShootNoneBullet()` (found beside `get_isGunShootEmpty`): a BLANK SHOT, the full gunshot sound
  (-9 dBFS, the shot's long tail) and the rifle-steady script logged it as a shot. Not the empty click; off (DRY_GAME_SHOT false).
- The LEMI shot dry with every spare round taken out of the inventory (tools/sim/zz_test_noammo.lua): each pull played only our
  click; the sounds script heard nothing from the game but a movement rustle. The game kept asking to reload.
- 224 empty-click name guesses (SND_MOT_RI3046_SE_EMPTY and kin, tools/sim/zz_test_wwise.lua, WwiseContainer.exists(String))
  found nothing; the check itself finds real names (SND_MOT_RI3046_SE_RELOAD_A on the LEMI). The containers' name lists are
  empty in the shipped game, and the gunshot's own name was not found either (161 guesses): the shot is not a motion sound.

## So
No game empty click turned up; Village reloads by itself instead of clicking. Ours stays. If a game sound is wanted instead, a
short click the game does play (a revolver's hammer, SND_MOT_RI3008_SE_MVT_PRE_SHOT, or a slide stop) could be given job 12.

## Later the same day: the hammer, and quiet while the game clicks (build b035)
Tefa: "it doesn't sound like the gun click sound unfortunately, so if you can swap every empty click sound for a short one like
the hammer being cocked ... the game also plays an empty sound once, sometimes multiple times before going quiet, so the hammer
cocking sound cannot play with the games own sound and must only play once the gun is quiet".
- The click is now the game's own M1851 hammer cock (SND_MOT_RI3008_SE_MVT_PRE_SHOT, wwise 740255369), played on the revolver by
  tools/sim/zz_test_trigger.lua and recorded with tools/sim/rec.py: 133 ms (a light click, then the catch), at -13 dBFS, the
  level the game played it at. sfx/dry_hammer.wav; the old dry_click.wav is kept.
- The game's own empty sound: heard once, on the first empty pull of the F2 run dry WITH spare rounds (-26 dBFS, our click muted
  by the dry_click_off test switch), then nothing on eight more pulls [verified-live 2026-11-01, n=1]. Never with no spare rounds.
- So each empty press now waits DRY_WAIT_S (0.12 s): the sounds script bumps a shared counter on every gun sound the game plays
  (bridge slot 182, not our replays, not footsteps); if it moved, ours stays quiet ("the game played its own sound for this press").
  On the repeat run the game made no sound of its own, so the hold-back is unproven: if Tefa still hears both together, the game's
  empty sound does not pass through the sounds script's hooks and needs another way to be seen.
