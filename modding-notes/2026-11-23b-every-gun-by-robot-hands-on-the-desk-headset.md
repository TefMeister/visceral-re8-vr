# 2026-11-23 (morning, /lm, PC1, Fable): every gun checked by robot hands, the real headset lying on the desk

Tefa: set the RE games to the slower render mode so the picture shows on the monitor, even the holster spots out like
RE2's, then every gun in RE8, RE2 and RE3: (1) grip zones, (2) magazines / reloads / racking (both slide sides),
(3) the hand and finger poses through reload and rack ("the big ask"). Later the same morning: a save with every weapon
on a free slot in each game. This note is Village; RE2 and RE3 were not reached in this sitting.

## The method (new, works)

- **Two Frame Sequential (`VR_RenderingTechnique_V2=1`) through the real headset (Virtual Desktop), the headset lying on
  the desk: the game's desktop window repaints** (Single Frame Multipass leaves it frozen, Tefa) `[verified-live
  2026-11-23, n=1 run of about an hour]`. Set in Village, RE2 and RE3 (old files:
  `D:/claude video game stuff/backups/re-render-2026-11-23/`). The simulator still needs `=2` (KNOWN.md): two different rigs.
- VR Bench's hands work on the real runtime: its room numbers are the same space as `vrmod:get_transform` (controllers
  read back exactly as written), and the drawn hands sit ON the controllers (on the simulator they were 40-50 cm off).
- Launch: `vrbench.py start <re8.exe>`, start `re8.exe` with `SteamAppId=1196590` and NO `XR_RUNTIME_JSON`; then the old
  drive (A, A, left stick up, A, 30 s, A) by `vb.py` / `stick.py`.
- New tools in `dev-archive/native/tools/sim/`: `keep.py` (keeps `pose_now.json` alive with a wobble, so hands never
  "sleep"), `hv.py` (poses in head-view numbers: right / up / forward of the headset), `guncheck.py` (one gun: every zone,
  fire until empty, magazine out and in, the spare swap, rounds; log lines per stage, pictures with `pics`), `snap.py`,
  `look.py`, `sheet.py`, `pose.py` (writes a Hand Poser pose file in the app's folder AND the game's copy),
  `q_giveall.lua` (the dev-guns button's code for `rv.py -f`).
- **Views that show the hand:** the headset cannot look down, so the arm hides the hand in most holds. What works: the gun
  across the view pointing left at 0.30-0.32 m (`hv.py right=0.05,0.03,0.32,90,55`), and for the hand under the grip the
  gun ROLLED -70 (`...,90,55,-70`): the camera then looks up at the grip and the left palm. A slide hold seen side-on is
  hidden by the sleeve; not solved (ask Tefa to prop the headset tilted 40 degrees down, or use the simulator's free head).
- `vrmod:set_rotation_offset` with a pitch did not tilt the view (only a small yaw came out).
- `StartSave` by script: `app.SaveLoadManager` `StartSave(Object, UInt32 type, Int32 slot, Boolean, Boolean)` with
  type = `app.SaveLoadType.GameSlotHash` (3385129124), slot 6, false, false, THEN `SaveAppSlotRequest()`: wrote
  `data006Slot.bin` `[verified-live 2026-11-23, n=1; not yet loaded back]`. Saves backed up first
  (`save-backups/village-2026-11-23-before-all-guns-save`).

## Holsters

Village's code already had RE2's six-spot numbers; the uneven part was the saved Holster Zones file of the seated evening
(2026-11-14: each spot moved and sized on its own). `holster_zones.json` reset to no per-spot moves, ammo pouch 20 cm
like the rest; SITTING (30 cm forward) left ON (Tefa's call; RE2 has none). Old file:
`D:/claude video game stuff/backups/re8/2026-11-23-before-holster-reset/`. Still different from RE2: the native ammo
pouch and the torch spot take no SITTING shift, the medicine reach is 16 cm, the leave margin 8 cm (RE2 6).

## Found

1. **The old magazine "flies out of the hand" (RE8-006): reproduced 4 of 4** with the hand held still for 1.5 s before
   LG was let go: "speed 2.50 / 2.58 / 2.83 / 5.52 m/s" (two later ones 1.1). The speed was taken from the DRAWN hand,
   which jumps when its owner / pose changes at the let-go. Fix built (not yet run): `reload_throw.cpp` samples the
   CONTROLLER (room space, turned to the world) `[compile-verified 2026-11-23]`.
2. **M1911, V61, S.T.A.K.E, Samurai Edge (and by the same defaults the USM-AI): the slide could never be taken.** Their
   zones were the unplaced defaults, 7-10 cm from the magazine, whose 12 cm reach always won ("the magazine first").
   The LEMI's zone layout copied to them in `zones.json` (old file kept beside the holster backup): the M1911's slide
   is then taken in both spheres and racks `[verified-live 2026-11-23, n=1]`; the other four not re-run yet.
3. The LEMI passes everything: mag / well / slide / slide-left, the pull, the rack after emptying, magazine out with B and
   back with LT, the spare swap (spots 19 -> 17 -> 18 -> 16 -> 13), 12 shots `[verified-live 2026-11-23, n=1-2]`.
4. The LEMI's magazine poses in Hand Poser ("ready on magazine", "magazine in hand", "spare in hand, magazine still in
   the gun") were the relaxed hand with only the index bent: never really posed. A first curled hold written for
   "ready on magazine" (fingers F1 -60..-70, F2 -65..-70, F3 -35; thumb barely changed). The old files:
   `D:/claude video game stuff/backups/re8/2026-11-23-hand-poser-before-claude-poses/`.
5. The LEMI's Hand Poser files, dock poses, magazine hold and slide hand were copied to the five other slide pistols
   where they had none (330 pose files), as a start for Tefa's fine-tuning.
6. Newly given guns arrive empty (0 loaded), and only 1 of 6 ammo stacks went in (the case is full).

## Later the same morning (b145)

- **b145 installed** (`builds.py`: reload/v0.1.0-b145): the throw fix. Run: LG let go with a still hand now hands the
  magazine over at **0.04 and 0.05 m/s** (LEMI spare swap, F2 magazine) `[verified-live 2026-11-23, n=2]`.
- **The all-guns save: slot 6, written by the game's own typewriter** (the Altar save loaded from the Load Game list,
  `q_giveall.lua` gave 9 guns + 4 of 6 ammo stacks to the 7 it had, A at the typewriter, slot 6) `[verified-live
  2026-11-23: the list showed slot 6 NO DATA before, both save files written 10:33; not loaded back yet]`.
  ⚠️ The scripted save (`StartSave` + `SaveAppSlotPrepare` + `SaveAppSlotRequest`) writes a `data006Slot.bin` the game's
  list shows as NO DATA: it lacks the slot's header (`SaveViaStart` takes a `SaveFileDetail`). Use a typewriter.
  "Continue" loads the autosave, not the newest slot.
- **Main menu by robot stick: a push of 0.1 s moves TWO rows** (Continue -> New Game: the Difficulty screen came up
  twice; nothing was confirmed the second time, the first time a new game's intro ran on a black screen and was closed
  before any autosave). `flick.py <dir> [n]` pushes 30 ms = one row. Load Game: A (title), flick up 2 = New Game, flick
  down 1 = Load Game, A, flick down n, A, A (Yes), 35 s, A. VR Bench's B did not back out of the Difficulty screen.

## Every gun, mechanics (guncheck.py; `[verified-live 2026-11-23, n=1]` unless said)

| gun | zones that took the hand | reload | rack | open |
| --- | --- | --- | --- | --- |
| LEMI | mag, well, slide, slide-left | B out, LT in, spare swap | both sides, after emptying too | - |
| M1911, V61, S.T.A.K.E, Samurai Edge | mag, well; slide ONLY after the LEMI's zone layout was copied (M1911 re-run; the other three not re-run) | B out, LT in, spare swap, "trigger refused until the rack" after | M1911 both sides | re-run V61, S.T.A.K.E, Samurai Edge |
| USM-AI | mag, well, slide, slide-left (with the copied layout) | all, 17 rounds | both sides, "was needed: it fires again" | - |
| F2 | mag, well, grip; bolt zone takes the MAGAZINE when no rack is due (by design, 12.7 cm apart) | LT pulls it out, drop | not reached (my step order pulled the magazine first) | bolt after a real empty, pouch magazine in |
| WCX, Dragoon, SYG-12 | mag, well | LT pulls it out, drop | not reached (same) | slide zone, pouch magazine in |
| W870, M1897 | pump (well: "too far" from the pump, right) | not run (the step looks for an insert zone; shells go in at `well`) | pump cycle complete, hand stays on | shells from the pouch |
| Wolfsbane | handle (palm on the hammer) | not run (its own loading-gate flow) | - | fire + gate loading by robot |
| Handcannon | handle and drum: NO log line at LG or LG + LT | "is closed: open it first" at the pouch | - | ⚠️ why the drum / hammer do not answer the robot hand (the walker measures the drawn hand, the dock the controller: try `feel.py`) |
| GM 79 | insert found | pouch gave nothing (no grenade rounds in the case) | - | rounds, the break |
| Rocket Pistol | no zones (none expected) | - | - | - |

Newly given guns are empty, so "fire until empty" fired 0 on them; the LEMI fired 12, the USM-AI 17.

## Hands (the big ask): where it stands

Not done. What exists now: a view that shows the hand under the grip (roll -70), `pose.py` + `look.py` for a
write-and-look loop, one first curled pose (LEMI "ready on magazine"), and the LEMI's poses copied to the other five
slide pistols. Still to pose per gun: "spare in hand, docked on the magazine" (17), "pulling the magazine out" (18),
"two magazines in hand" (16), "magazine in hand" (13); the thumb's axes are not understood yet (Thumb2 / Thumb3 `y` +50
changed little on screen). Tefa's wish that the middle finger and thumb close as the magazine comes out needs the pose
to follow the pull distance (today a pose changes with the spot, eased by time): a small change in `hand_poser.lua`.

## Afternoon (same day, Tefa: "please use all the poser family tools for all this, and tweak the tools themselves")

- **The poser tools take input from outside now** (nobody at the mouse): Hand Poser `remote.json` (joints, the MAGAZINE IN
  HAND box, the new SPARE MAGAZINE box; hand-poser-vr 04da823, 1bc5139), Grip Zones `zones_remote.json` (grip-zones-vr
  730ffff). `tools/sim/pose.py` and `zone.py` send them; the windows must be open (minimised is fine, and it has to be:
  opened, they sit on top of the game and `shot.py` photographs them instead).
- **b146** (builds store reload/v0.1.0-b146): (1) the F2 empty could not be reloaded: LG at the magazine, 13 cm from the
  bolt, always went to the bolt ("a rack is due" was also true for a merely empty gun). Now on an EMPTY gun the nearer part
  wins; a round waiting for the rack or a bolt mid-cycle wins as before. Run: magazine out, pouch magazine in, 6 rounds,
  "trigger refused until the rack" `[verified-live 2026-11-23, robot, n=1]`. (2) `visceral_re8_mag2.lua` reads `mag2.json`
  again twice a second while a magazine copy is drawn `[verified-live, twelve places set from outside and seen]`.
- **The all-guns save keeps 11 guns.** USM-AI, Rocket Pistol, Handcannon, Dragoon and WCX (the bonus-shop guns) are gone
  after every load, also with a bigger case `[verified-live 2026-11-23, n=3 loads]`. The case itself can be made bigger for
  good: one more "case extension" item (id 269218988, `createAndAddItem`, then `Inventory.restoreExtendLevel()`): 13x8 ->
  14x9, kept by the save. `visceral_re8_dev_guns.lua` (testing only) now gives the missing guns again by itself 10 s after
  any load (16 guns counted after a load `[verified-live, n=2]`); off: delete `visceral_re8/dev_guns_auto.txt`.
- **Slide pistols:** V61, S.T.A.K.E and Samurai Edge re-run: both slide spheres take the hand and rack `[n=1 each]`, so all
  five work with the LEMI's layout.
- **Long guns:** WCX and Dragoon pass (slide, magazine out with LT, pouch magazine in, then the rack is asked for). SYG-12:
  its slide zone sat 5 cm from the magazine's and the magazine always won; through the Grip Zones window the magazine zone
  went 8 cm down and to 9 cm (well 9 cm): the handle is taken, "was needed: it fires again" `[verified-live, n=1]`.
- **The LEMI's reload stages have a first pose each, set through the Hand Poser window:** ready on magazine, magazine,
  spare in hand (19), spare docked (17), pulling out (18), two in hand (16), magazine in hand (13). Fingers: `z` negative
  curls (F1 -45..-80, F2 -50..-85, F3 -25..-48); the thumb: `Thumb2.y` / `Thumb3.y` positive bends it, `Thumb1.z` toward 0
  brings it across the palm `[measured on a free hand held side-on, 8 pictures]`. Coarse: judged from one camera angle.
  The spare's place in the docked stage looks wrong (it hangs under the wrist, not between index and thumb): it has
  sliders now (SPARE MAGAZINE box) and is left at its old numbers for Tefa's eye in the headset.
