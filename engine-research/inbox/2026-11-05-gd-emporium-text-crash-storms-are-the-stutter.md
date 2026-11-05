# The Emporium's text writes crash in bursts, and those bursts are the stutter

From: Gold Digger (`/gd`), dev PC, 2026-11-05, reading the home PC's collector shelves
(`runs`, `performance`, `logs` for visceral-re8-vr; 23 run cards, 20 perf recordings, 25 game logs).

## What the logs show

- **`via.gui.Text.set_Message` throws an access violation hundreds of times a minute while the Emporium is open**
  `[measured 2026-11-05]`. REFramework catches each one (`VMContext: Caught exception code c0000005`), dumps a full
  call stack and rescans modules every time, so `pcall` in our Lua does not make it cheap. Counts per game log:
  - `2026-11-04_20-48-49_PC1_re2_framework_log.txt`: 1012 (20:47 to 20:48)
  - `2026-11-04_21-10-50_PC1_re2_framework_log.txt`: 2600 (1084 at 20:52, 984 at 20:53, 428 at 20:54, 104 at 21:09)
  - `2026-11-05_08-54-51_PC1_re2_framework_log.txt`: 200 (08:54:03 to 08:54:13), starting right after
    `[visceral-emporium] pick: mode (Customize) ... real screen 2 passed through` and `hide seen on app.GUIShopMenu`.
  - Every earlier log with Emporium picks (18:47 to 20:16 on 11-04): 0. The two 11-05 runs after the row-redraw
    build (12:19, 12:34): 0, but neither opened the Emporium, so they say nothing about whether it is gone.
- **The storms line up minute for minute with the worst stutter the perf recorder caught** `[measured 2026-11-05]`:
  - 20:16 run: 95 fps steady for 30 minutes, then 20:47 = 38 fps and 242 stutters in that minute.
  - 20:48 run: 20:51 to 20:54 = 38 fps, 240 stutters a minute (1442 for the whole run, the most of any run);
    back to 95 fps with 0 stutters from 20:54 on.
  - 08:53 run: 180 stutters in two minutes, and the collector logged the one 5 s hang of all 23 runs.
  - During a storm the processor use halves (about 370% to 190%) and the graphics card clocks down
    (2400 to 1450 MHz, 125 W to 68 W): the game's main thread is stuck in the exception handling, the rest waits.
- **A second stutter stretch is NOT explained by this:** 21:06 to 21:08 on 11-04 (217 then 457 stutters) had no
  set_Message storm. That minute shows the Emporium script reloading (`loaded; 12 setting(s)`) and opening Sell.
  `[hypothesis]` a script reload, or a different screen; not checked.

## What it probably means

`[hypothesis]` A `via.gui.Text` control we write to is no longer alive (the game swapped or freed the screen:
Customize/Gunsmithy, Sell) while `visceral_re8_emporium_shop.lua` still holds it (`set_text` at line 527, the
per-card loop at line 158) and writes every frame. Two things are worth knowing:

1. It may be part of the "little jump or jutter in between the selections" Tefa felt in the Gunsmithy on 11-05.
   The 08:53 run was the morning headset look; its storm is the Customize screen. The row-redraw fix (070f932)
   targets a different cause (the game re-laying rows); both may be true.
2. It costs nothing to check: the Emporium open in flat, then count
   `grep -c "invoke for via.gui.Text.set_Message" re2_framework_log.txt`. 0 = gone.

## Proposed board row

`[FLAT]` **Emporium: the text writes crash in storms (up to 1000 a minute) and halve the frame rate.** Check each
held Text control is still valid (the game object still alive, the screen still open) before `set_Message`, and
drop the handles when the screen changes; open Customize and Sell, then count the line above (should be 0), and
compare the perf recorder's stutters in those minutes. `MODEL: OPUS`

## Smaller things seen on the same shelves

- `re8_instructions/data/village_character_joints.json` fails to parse ("parse error at line 1, column 1") twice
  every run since at least 11-04 22:19 (the holster scripts read it). Harmless so far; an empty or broken file.
- `via.Joint.get_Position` / `get_AxisX` internal exceptions: 553 in the 19:37 run, 197 in the 08:53 run, 200 on
  11-03. Older than the Emporium; not looked into here.
- Three run cards say `ended: lost, 0 s` (11-04 21:20, 11-04 22:39, 11-05 10:05): the BeG0nE helper was down when
  the game closed. All three are before the home PC loaded Lanes 0.100.0 (10:46), which carries the fix; none since.
- The 08:53 run also used much more memory than any other: 10 GB of graphics memory (others about 6.2), 16.6 GB
  private (others about 13), 163 threads at start (others 91 to 115). Not explained.
