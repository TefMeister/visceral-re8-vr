# 2026-11-26e: the recorders in rebuild 2, the legs' halving test made ready, the lean fix designed (/pd, Fable, Build PC)

Board rows RE8-091 and RE8-092. **The game was not launched and nothing here has been run in it.** Everything is
`[compile-verified 2026-11-26]` unless a line says more. Build `rebuild 2/v0.1.0-b189`, installed, not started.

Tefa's words for this job: *"wire the jitter recorder and Ghost Hand into rebuild 2 the way Lanes says every VR mod has
them, so a walk in the headset leaves measurements. Then prepare the halving test for the legs ... one per start.
Also RE8-092 while there: design the body-at-a-stop fix so it measures in the plugin where leanrec reads, and show it
working on the recorded numbers before I wear anything."* Plan shown and answered: *"8 yes"*.

## 1. The recorders (`native/src/rec.h`, `rec.cpp`; Lanes' `jitterlog.h` and `ghosthand.h` copied to `native/src/begone/`)

Run at PrepareRendering post, after the joint writer: the body as it is drawn. They read; no joint is written, nothing
is hooked, the game is asked for nothing. Only while the headset and the controllers are in use; a flat run writes
nothing. Switch in off.txt: `recorders`.

- **Camera Jitter BeG0nE**: the headset's pose, the camera's place and turn, one tick per picture, both controllers.
- **Ghost Hand BeG0nE**: both controllers and both drawn hands, plus the hip, feet and knees as "parts"; all in the
  head's own space (the controllers through the headset's pose, the game's things through the camera).
- **The walk file**, ours: `reframework/data/visceral_re8/walkrec/walk-<date>-<time>.csv`, one line per picture: feet,
  knees and hip in the PLAYER's own space, the first two motion layers' bank, number, frame and end frame, the left
  stick as the script handed it to the game, speed, head minus body, the flags (cutscene, hands, weapon, turn, room
  step, sleeping controllers, game arms), the drawn hands and the controllers, the lean fix's numbers. Its first
  line carries the switches that were off.
- New bridge slots 14 to 32 (`bridge.h`; the array is 40 long now): the stick, the room step flag, the headset's pose,
  the controllers' places, the lean ask and what was used, the script half's switch.

What is NOT established:
- **The headset's pose is the loader's copy**, written by the script at UpdateHID (the plugin API hands a plugin no
  pose): the jitter report's "pose age" is measured from that copy, not from the runtime's read.
- The runtime is given as plain `openxr` (headset and simulator are not told apart; b178 did the same).
- The joint names `L_Foot`, `R_Foot`, `L_Shin`, `R_Shin` are taken from older kept logs of this game `[reported, our
  logs]`; the log line "recorders: joints ..." of the first start says whether all were found.
- `via.motion.Motion.getLayer(UInt32)`, `getLayerCount()`, `via.motion.TreeLayer.get_Frame / get_EndFrame /
  get_MotionID / get_MotionBankID` exist with those parameter counts `[inferred-static 2026-11-26, tdb-read.py on the
  exe]`. Whether a float comes back in four bytes or as a double is not known: both are written, the reader takes the
  one that reads as a frame number. Whether layer 0 is the walk is not known either (two layers are written).
- The cost per picture (about 25 calls into the game, three file writes) is not measured.

## 2. The reader (`tools/walkread.py`)

Counts, over the pictures in which the player walks: the walk motion starting over mid-way, a foot or knee snapping in
one picture, the hip snapping (the whole body moved), drawn hands that hold and jump; and what each leg snap came
together with (a restart, a new motion, the stick changing, a room step, the cutscene flag, a body snap, a long
picture). `walkread.py selftest`: nine made-up cases, all right `[verified-numerically 2026-11-26]`: a clean walk
counts 0 (the motion's own loop at its end is not a restart), a walk starting over every 22 pictures counts 4.06
restarts and 4.06 leg snaps a second, 0.244 s apart. Its limits (40 mm, 4 times the usual step) are first guesses, not
tuned on a real walk.

## 3. The halving test (`tools/legs-test.sh`)

`frame` in off.txt never switched off the script half (the body's place and the steps are in
`visceral_re8_bridge.lua`): "the bare base" was not bare. New: `scriptbody-off.json` beside off.txt (the script reads
it at its start; the loader's own placing and slide stand then). `frame` now leaves the bridge reader, the player
finder and the recorders running, so the bare base can be measured.

One per start: `all-on` (start 0), `bare` (frame + scriptbody), `frame`, `bodyturn`, `bodyturn-walk`, `spinestill`,
`scriptbody`; `status` prints one counted line per walk file. How to read the outcomes is at the top of the script.
Set now: everything on.

## 4. The lean fix (RE8-092): `native/src/leanmath.h` (the sums), `leanfix.cpp` (the measuring), a hook in the script

Measured at PrepareRendering post, on the body as drawn (where leanrec reads): the neck's level distance behind the
eyes. Our own move and the loader's look-down shift (0.10 m at straight down `[read, RE8VR.cpp, the March source]`)
are taken out; what is left is compared with the distance while STANDING, which is learned in play (0.6 s of standing
with the reading steady within 2 cm, then followed slowly), never assumed. What a motion takes it below that, past a
4 cm dead band, is asked as "the body sits this much further back" (out in 0.05 s, back in 0.30 s, never more than
20 cm, nothing in a real scene, nothing before the standing distance is learned). The ask goes to the script (slot
30), which adds it behind the head in its body placing ONLY when `bodyplace.json` says `"lean": 1`, and says back
what it used (slot 31). Built-in: `lean` 0 = it measures and the walk file records what it WOULD do.

Shown on numbers, the SHIPPED sums compiled into `native/tests/leanreplay.cpp`:
- `leanreplay selftest`, twelve made-up cases, all right `[verified-numerically 2026-11-26]`: a 12 cm lean in 0.2 s
  (neck 16 cm to 4 cm) reads 9.1 cm at its nearest with the fix; standing, looking down, a real scene, a teleport
  reading and "nothing learned yet" ask for nothing; walking between 11 and 18 cm asks for 0.8 cm at most.
- The kept logs' `lean:` lines `[verified-numerically 2026-11-26, a MODEL of the recordings, see below]`:

  | kept log | stop windows | neck nearest as recorded | with the fix | typical stop |
  | --- | --- | --- | --- | --- |
  | 18:23 (b186) | 82 | -22 cm | -7 cm | 4 to 7 cm becomes 13 to 14 cm |
  | 19:00 (b187) | 17 | -3 cm | 11 cm | 3 to 7 cm becomes 12 to 14 cm |
  | 17:35 (b185, before the false-cutscene fix) | 25 | -12 cm | 7 cm | -9 to 2 cm becomes 7 to 11 cm |

  The -22 / -7 cm windows are jumps of 18 cm and more inside half a second (the vault or a real scene's
  end): the fix's 20 cm limit and its 0.05 s do not cover them.

What is NOT established:
- **The recordings are half-second ranges, not frames.** Each window is rebuilt as a path (in fast over the first 40%,
  out slow) and the sums run over it at 90 pictures a second. The frame-by-frame proof is the walk file.
- **The one assumption**: moving the body's place by x moves the neck by x on the next picture. The check on the walk
  file, once `lean` is 1: `lean_raw` stays level while `lean_applied` changes.
- **Walking.** In the 18:23 log, of 33 walking windows that leanrec wrote down (it wrote only windows in which the
  neck moved more than 4 cm, so quiet walking is not among them) the neck's nearest was 12 cm or more in 11, 9 to 11 cm
  in 13, under 9 cm in 9: the fix would also move the body back by a few centimetres in some walking moments. Whether
  that looks right or wrong is not known; the walk file will show how often.
- The look-down shift's size in the nightly (read from the March source only). The vault: never measured.

## 5. Changed by the way

- The script's built-in numbers are now follow 0.05 s and dead zone 0 (were 0.9 s / 1 cm): Tefa, asked whether the
  live setting stays: *"standing still felt fine"* (and *"still fine"* twice during the test). The game folder's
  `bodyplace.json` already said so.
- The other window's game (b188, left running) was closed by its own window close before the install; its log is kept
  as `~/visceral-kept-logs/re8-2026-11-26-1925-b188-last-run.txt`.

## 6. For the walk (/ms)

1. Start 0 is set (everything on). Tefa starts the game, walks about 20 s the way the clip shows, stops from a run
   three or four times, vaults a fence if one is near.
2. After the game is closed: `python dev-archive/rebuild2/tools/walkread.py`, then `begone.py new`.
   The game's log must hold "recorders: joints all found; the player's motion found" and "recorders: on".
3. The numbers decide the next start (`legs-test.sh`), and whether `"lean": 1` is worth wearing.
