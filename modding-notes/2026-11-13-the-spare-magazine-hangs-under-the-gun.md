# The spare magazine hangs under the gun (2026-11-13, PC1, Opus; b118 + b119)

Tefa, 2026-11-13, after wearing b117 (clip "Lemi 2 mags re8"): *"Lemi 2 mags works, techincally in re8!! ... but the extra mag
follows my view and doesn't sit in my hand when taken out of the pouch. also the ammo counters are still wring and not
updateing when mags or shells are being inserted."*

## What the clip showed

Read frame by frame (4 a second): the spare from the pouch hangs at one spot low on the right of the view and turns with the
head; the gun's own magazine, pulled out with B, sits in the hand. The log of that run has every two-magazine step firing
(spare taken, swap, new magazine filled from the carried ammo, old one dropped). Log kept:
`D:/claude video game stuff/village-logs/2026-11-13_1743_lemi-2-mags.txt`.

## Cause and fix

- The spare (a copy of the gun's mesh, `lua/visceral_re8_mag2.lua`) was written in the WORLD from the hand's place the plugin
  handed over. The gun's own magazine is written in the GUN's space (`pose_joint`, `to_weapon_local`) and was right in the
  same clip. The copy's world place came out where the game's animation keeps Ethan's left hand (by the camera), the same
  family as the slide fault of 2026-11-09 (read before the arms are solved). `[inferred-static]` for the exact timing; the
  fix does not depend on it.
- b118: the plugin hands over the hold in the gun's space (`pose_second`); the Lua hangs the copy UNDER THE GUN
  (`via.Transform.set_Parent`, local zero) and writes the magazine joint in local space (Body, its parent, pushed 100 m down
  locally), at PrepareRendering and BeginRendering only. The Lua's "drawn here" reply is in the gun's space too
  (`insert_from` takes it as is). A once-a-second `check:` log line.
- b119: in b118 the copy could not be hung under the gun: a Village gun (`app.WeaponGunCore`) is an item with no
  `get_GameObject`; its object is `get_owner()` (as `player.cpp` already does). Without the parent the copy was drawn in the
  world from gun-space numbers (wrong). Fixed in `held_gun`.

## Seen

- `[verified-live 2026-11-13, simulator + VR Bench, n=1, LEMI]` `twomag_test.py` 11 of 11 steps; log `the copy hangs under the
  gun (set_Parent)`; with the head and the gun still and only the left hand moving, the copy's distance from the camera moved
  0.60-0.84 m (before the fix it would sit at one place by the view); docked on the seated magazine it sat 8-9 cm from it
  (the second place, 3 cm, plus the hold). Log kept: `.../village-logs/2026-11-13_1856_b118-twomag-sim.txt`.
- NOT seen: the spare in the headset; whether it sits in the palm right (the simulator draws the hands out of view).
- The `check:` line's "gun's own magazine" reads a constant 0.733 m from the camera even while it is in the hand: that read
  (the owner's transform `getJointByName`) is not a trustworthy reference; the camera distance is the useful number.

## Not done: the ammo counter

The log shows the keep-right refresh (`applyToUI`, `showRemainAmmo`, `updateRemainAmmo`) running every 2 s without an error
and changing nothing: the counter does not read the number our reload changes, or waits for something a shot sets off. Fifth
report (10-19, 10-31, 11-02, 11-09, 11-13). Next is a live look at what `app.GUIRemainAmmo` reads after our reload vs after a
shot. `MODEL: FABLE`.

## Tools fixed on the way

- `tools/sim/drive.sh` switches the VR Bench layer on itself (it had been left off: every robot press went nowhere); on a
  wrong menu it takes a picture first, and `KEEP_ON_WRONG=1` leaves the game running.
- Learned: the guard's "true app.GUITitle" / "GUIDialog" can be stale while in play (check `re8vr.weapon` or a simulator
  picture); keyboard Enter / F / Up drive the menus when the robot pad does not; two starts in a row froze at REFramework's
  "Initializing WindowsMessageHook" (thread suspend) right after a close, the third was fine (FAULTS row).
