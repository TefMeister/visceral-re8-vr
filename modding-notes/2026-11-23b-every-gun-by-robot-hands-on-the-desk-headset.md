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
