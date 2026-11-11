# Two shells in the hand, and a palm of rounds for the Wolfsbane (2026-11-11, PC1, Fable)

Tefa, 2026-11-11: *"can you get 2 shotgun shells to show up for the shotgun in re8? and so they dissapear one after another
when inserted into the gun. only one if it's the last one in the pouch or if gun only needs one more. same with wolfsbane, to
have as many ammo in the palm of hand, as is either needed to fill the drum or amount in the pouch if player has less in the
inventory than the gun actually needs"*.

Build b111. Compiled and installed; **nothing here has been seen in the game yet** `[compile-verified 2026-11-11]`.

## What was already there

- The COUNTS were already right `[inferred-static]`: a shotgun pouch grab takes 2 shells, or 1 when 1 is carried or 1 fits
  (`shells.cpp grab_count`, 2026-11-02); a Wolfsbane grab takes `min(free chambers, carried)` (`gate.cpp`, 2026-11-01).
- Only ONE was ever drawn: the shotgun has one loose shell joint (W870 `ShotgunCartridge_FK_0`, M1897 `Bullet`); the
  Wolfsbane drew one chamber's round joint at the right fingertips.

## The Wolfsbane: the rest of the grab lies in the right palm (`drumrounds.cpp`)

- The round that goes in next stays between the thumb and index tips (the tuned spot). The others are drawn in a row across
  the palm with the round joints of chambers that show nothing now (emptied by us, or not loaded by the game's count).
- RT at the cover: the fingertip round travels in; when it is home the next one moves up from the palm, so the palm loses
  one per round put in.
- The palm's place uses no axis of the hand joint: `R_Hand`, `R_IndexF1`, `R_PinkyF1` give "along the fingers", "across" and
  "out of the palm" (cross product; the sign assumes right-handed axes `[inferred-static]`). A round's long axis is the
  barrel's line while it rests in the drum; it is turned onto the fingers' line.
- Tuning without a rebuild, `lid_swing.json` (read at every cover opening): `"palm_off": [along, across, out]` in cm
  (default `[0, 0, 2]`; a negative third number puts them on the other side of the hand), `"palm_step"` cm between rounds
  (default 1.3). The menu's "round in the hand" size slider sizes them all.
- A FULL hand (5 rounds, empty drum) uses every round joint, so a falling spent case borrows one from the palm for its fall
  (one round fewer there for about a second). `cover_now` no longer needs a free chamber to read a round's turn.
- Log lines: `drumrounds: N round(s) in the right hand: M drawn (1 at the fingertips, K in the palm)`.

## The shotgun: the second shell is a copy (`visceral_re8_shell2.lua`, `reload_pose.cpp`, bridge slots 217-225)

- The plugin says each frame "a second shell is in the hand" (2 or more counted, a shell-port gun) and where the first is;
  the script draws a copy of the gun's mesh with only its shell left in sight, beside the first. First shell in: the count
  drops to 1, the copy goes, the gun's own shell is the one left.
- **Which mesh part holds the shell** `[measured 2026-11-11, flat, n=1 per gun]` (one part on at a time, the gun's `Body`
  joint moved 100 m down, the shell joint written 0.35 m in front of the camera, green pixels counted, then by eye):
  - W870 (ri3021): **part 50** is the shell alone (the LEMI's rounds are its part 50 too); the gun is part 0. Parts 1 and 3
    are off in play and show nothing.
  - M1897 (ri3036): the live shell (`Bullet`) is in **part 0, with the whole gun**; no part shows it alone. `EmptyBullet` is
    a fired, opened shell (another model).
- So the copy does not rely on parts alone: its `Body` joint (every other piece hangs under it) is put 100 m under the
  floor and its shell joint is written straight to the second shell's place. A copy made with `via.GameObject.create` +
  a `via.render.Mesh` component HAS the mesh's joints and they take writes at LateUpdateBehavior `[measured, both guns]`.
- Seen on the flat screen, both guns `[verified-live 2026-11-11, flat, n=1 each]`: the copy's shell alone in front of the
  camera (test file), and the pair, the gun's own shell with the copy 2.2 cm beside it, when the script is told a second
  shell is in the hand (the bridge slots written by hand through the live question line). Pictures looked at, not kept.
- NOT seen yet: the real thing in the headset (pouch grab of two, where the second lies against the hand, one going away per
  LT). The 2.2 cm is along the shell joint's own x; whether that is "beside" or "on top" in the palm is for the headset.
  Sliders: REFramework menu, "Visceral RE8 second shell" (move, turn, per gun).
- The Mercenaries / Rose variants (3085, 3084, 3147) take their base gun's part by likeness `[hypothesis]`.

## Driving notes from the run

- `tools/sim/flat_boot.sh` launches flat (also with a headset streaming) and drives into the save; worked twice.
- `app.GUIManager.exclusiveTarget` keeps saying `app.GUIDialog` after the load: it does not tell "in play". The player's
  transform answering does.
- The bridge's camera slots (72-78) are empty on the flat screen; the game's primary camera works there.
