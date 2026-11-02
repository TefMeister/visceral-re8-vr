# 2026-11-02 afternoon: every gun's own finger poses recorded; the performance recorder's first run

Home PC, `/lm`, Opus, flat (no headset), 13:35-13:46. Builds b054 (performance recorder) and b055 (finger recorder
with `guns` / `equip`).

## What was done

- **The finger recorder** (`dev-archive/native/lua/visceral_re8_finger_rec.lua`) recorded two takes per gun: holding it
  (`draw_idle`, ~4.7 s) and a full reload from empty (`reload_full`, 7.8-13 s). 160 joints per frame (finger joints of the
  player and the upper-body mesh, local rotations). The four quick-slot guns went by number keys; the rest by the new
  `equip <id>` command, which calls Andyalpa's proven native equip (`__re8_holster_equip_item`).
- **11 guns + the knife's grip** (first launch; "12 guns" said at the time was a miscount) `[verified-live 2026-11-02, n=1 take each]`: W870 TAC ri3021, LEMI ri3046, M1897 ri3036,
  F2 Rifle ri3042, M1911 ri3040, GM 79 ri3023, M1851 Wolfsbane ri3008, V61 Custom ri3047, S.T.A.K.E ri3050, SYG-12 ri3048,
  ri3122 (not in weapons.cpp's list yet), knife ri3022 (grip only, no reload). Every reload take runs from the reload's
  first motion back to rest: the shotguns and the Wolfsbane load round by round (motions 2511 start, 2512 per round, 2513
  end); the rest play one reload motion (2500). 96-186 of the 640 rotation values move during a reload; 0-18 while holding.
- **ri3051 was refused** by our own equip guard ("an app.WeaponCore of a kind the plugin does not know"): not a gun,
  probably a throwable `[inferred-static]`.
- The V61 Custom's holding take caught an automatic reload (it was drawn empty); its reload take is clean.
- The takes are game animation data, so they stay OFF GitHub: kept locally (finger-takes/2026-11-02 in the work folder,
  25 files, 89 MB).

## The performance recorder's first run

`perf-2026-11-02-133542.csv`, 11 minutes, flat: one line every 2 s as designed, video memory found, 81-87 frames a second,
no stutters over 25 ms while playing; private memory ~14.0 GB, video memory ~7.1 GB `[verified-live 2026-11-02, n=1]`.
The reader first called the normal close "stuck" (the game draws nothing for ~12 s while it shuts down); fixed: frames at
zero while memory is being let go is read as a normal close.

## Next

Step 2 and 3 of the board row: turn the takes into clips and play them on the docked hands' fingers while our code places
the hand. That is the part nobody has written down for RE Engine (how the motion layers drive the finger joints).
`MODEL: FABLE`.

## Second launch (13:55-13:59): the five guns the save did not have, so ALL 16 are recorded

Tefa: "can you do it for all the weapons in the game". The save held 11 of the 16 guns in `weapons.cpp`'s list (not
counting the Mercenaries and Shadows of Rose copies). The recorder gained `give <number>`: an item by its id number,
the RE Engine name hash (murmur3_32 of the UTF-16LE name, seed 0xFFFFFFFF; the computed LEMI number 97158149 matched the
game's own ItemID), through `InventoryManager.createItemCore(id, 1, 0, 0)` -> `get_work()` -> `activeInventory.addItem`.
Testing only, on the modding save, which was backed up first (backups/village-save-before-give-2026-11-02 in the work
folder). Added and recorded `[verified-live 2026-11-02, n=1 take each]`: WCX ri3049 (2500), Rocket Pistol ri3115
(2511-2513), Handcannon PZ ri3116 (2511-2513), USM-AI ri3124 (2500), Dragoon ri3125 (2500). All takes are kept locally:
finger-takes/2026-11-02, 17 item ids (16 guns + the knife).

The reader's close test was still wrong on a fast close (the game left before letting go of its memory): now a run whose
frames stop and whose game is no longer running, with no crash on record, reads as closed.
