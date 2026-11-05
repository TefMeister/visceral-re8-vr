# The magazine looks as full as its own rounds (2026-11-05 afternoon, Fable, home PC, OpenXR Simulator + VR Bench)

Tefa, 2026-10-31: *"we need to change the mag that goes in full from the pouch when the gun is empty, also the mag in hand
changes to the empty model when that one last round is fired. the empty mag model should only be the one that comes out of
the gun when all but one ammo is depleted."* Board row `MODEL: FABLE`: "first find, live, what draws the rounds in a magazine".

## What draws the rounds `[measured 2026-11-05, simulator, LEMI]`

Read first from the saved type list (`type_probe.txt`, app.WeaponGunCore), then confirmed live:

- The gun mesh has a list of parts that VANISH when the magazine is empty: field `switchVanishEmptyPartsDisp`
  (List of part numbers), on when `IsEnableVanishEmptyPartsDisp`. The LEMI's list is one part, **50**: the rounds.
- The game switches them with `execSwitchVanishEmptyPartsDisp()` from the GUN's own round count. Logged live: with 2 and 1
  loaded the rounds part is on; with 0 loaded it is off. The magazine part itself (1) stays on.
- There is also a SECOND magazine part (`SecondMagazinePartsNo`, 11 on the LEMI; flags `IsSecondVanishEmpty` /
  `IsSecondVanishNoEmpty`). The LEMI's flag says "vanishes when empty", yet the game kept part 11 ON at 0 loaded, so that
  flag means something else than this switch (a reload-animation part?). Left to the game.
- The magazine in the left hand is the gun's own mesh (its `Magazine` joint moved to the hand), so the gun's count ruled its
  look: a pouch magazine in an empty gun's hand looked empty, and the pulled-out one emptied when the chambered round fired.

## What was built (b067, fixed in b068)

`src/magdisp.cpp` (+ `reload::mag_rounds_out()` in reload_pose.cpp): while the magazine is out of the gun (in the hand,
falling, going in), the rounds parts follow the magazine's OWN rounds: the one pulled out keeps what it left with
(`g_mag_rounds`), a fresh one from the pouch is as full as the carried ammo allows. Written after the game at the same
three points as the magazine joint; when the game switches the rounds off meanwhile (a shot at count 0), they are written on
again and the log says so. When the magazine seats, the game's own switch is run once so its look is the game's again.
The thrown copy (`visceral_re8_magthrow.lua`) gets the facts over bridge slots 203-212: its rounds, the second part when the
gun shows it, the vanish parts; it shows the rounds only when it holds any.

## Seen on the simulator `[verified-live 2026-11-05, simulator, n=1 each]` (`tools/sim/magdisp_test.py`)

- LEMI fired empty, right B: "magazine out with 0 round(s): shown EMPTY"; the copy "with 0 round(s) (empty look)".
- A fresh magazine from the pouch with the gun at 0: "out with 12 round(s): shown FULL"; the game switched the rounds off
  three times while it was in the hand, each time written on again.
- Brought to the well: seated, "new magazine: 12 rounds", "back in: the game's own look again (rounds 1)".
- Right B with 12 in: "drop with 11 rounds in it", "shown FULL"; the copy "with 11 round(s) (rounds parts on)".
- NOT exercised: the chambered shot with the magazine in the hand (the trigger was refused until the rack after the pouch
  magazine; the simulator's LG on the seated magazine landed 0.455 m off, so the release-into-hand path did not run). The
  mechanism is the same one the pouch case proved (the game's switch-off caught and undone). A headset look remains.
- The look itself was not seen in a picture (the held hand sat low in the simulator's view): `GATE: VR USER`.

## Other guns

Every gun's list and second part are logged once per gun (`magdisp: <gun>: rounds parts that vanish when empty [...]`): a gun
with no such parts gets nothing written. Only the LEMI was run.
