# 2026-11-02 afternoon: every gun's own finger poses recorded; the performance recorder's first run

Home PC, `/lm`, Opus, flat (no headset), 13:35-13:46. Builds b054 (performance recorder) and b055 (finger recorder
with `guns` / `equip`).

## What was done

- **The finger recorder** (`dev-archive/native/lua/visceral_re8_finger_rec.lua`) recorded two takes per gun: holding it
  (`draw_idle`, ~4.7 s) and a full reload from empty (`reload_full`, 7.8-13 s). 160 joints per frame (finger joints of the
  player and the upper-body mesh, local rotations). The four quick-slot guns went by number keys; the rest by the new
  `equip <id>` command, which calls Andyalpa's proven native equip (`__re8_holster_equip_item`).
- **12 guns + the knife's grip** `[verified-live 2026-11-02, n=1 take each]`: W870 TAC ri3021, LEMI ri3046, M1897 ri3036,
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
