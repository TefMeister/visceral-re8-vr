# Gold Digger, 2026-11-07: what the Village shelves of 2026-11-05 to 11-07 say that the notes do not

From: `/gd` inside `/fullscan` on the home PC (PC1), reading the visceral-re8-vr shelves (runs, guns, hands, logs,
performance, other), items shelved 2026-11-05 to 2026-11-07 00:15. Nothing here was tested live.

Supersedes: item 2 of `2026-11-05-gd-hand-recorder-spaces-and-empty-settings.md` ("three settings files were empty").

## 1. The "empty" settings files are MISSING files, not empty ones

`[measured 2026-11-07]` On the home PC none of these exist in the game's `reframework/data` folder:
`visceral_re8/magthrow.json`, `re8_vr_haptics.json`, `village_character_joints.json`, and the folder
`hand_poser/guns/` is empty. REFramework's `json.load_file` reports a missing file as
`[json.exception.parse_error.101] parse error at line 1, column 1 ... unexpected end of input` `[inferred-static]`
(it parses an empty read), which is why the 2026-11-05 note read them as "empty". The features use their built-in
defaults, as designed. Nothing is being cut short at exit.

The same message for Hand Poser pose files (newest log 2026-11-07 00:15 and the 11-06 ones): `no gun.json`,
`ri3008_Inventory @ hammer.json`, `@ drum.json`, `@ drum + right hand on the cover.json`, `ri3046_Inventory @ magazine.json`:
no pose saved for that gun and spot yet, so the pose in hand stays (hand_poser.lua `load_own_pose`). Harmless, but it
fills the log with errors.

Proposed board row (small, Hand Poser and the mod): `[PD] Check a file exists before json.load_file (fs.glob or
io.open) so a missing optional file logs nothing, not a parse error.`

## 2. A burst of game errors at the start of play and at quit, every run since 2026-10-31

`[measured 2026-11-07, n=6 logs]` "Internal game exception thrown in REMethodDefinition::invoke" in bursts:
about 50 in the first minute of play and 190 to 320 in the last minute before quit
(logs of 2026-11-06 00:32, 2026-11-07 00:03, 2026-11-07 00:15). Newest log, by method:
`app.WeaponCore.disp` 126 (System.InvalidOperationException), `via.Joint.get_Position` 42,
`via.GameObject.getComponent` 17, `app.PlayerWeaponChange.isRequestedBothHandTo{One,Both}Hand` 12 each,
`app.CharacterUpdater.get_equipController` 12, `via.Joint.get_AxisX` 11, `app.WeaponGunCore.resetMagazineDisp` 1.
`WeaponCore.disp` appears in logs from 2026-10-31, 11-01, 11-03, 11-06 and 11-07.
Reading: our per-frame code keeps calling the gun and the player while they are being built or torn down
`[hypothesis]`. No crash came of it in these runs (all closed with exit code 0), but a call on a freed object at quit
is the kind that can crash.

Proposed board row: `[PD] Find which of our files call WeaponCore.disp and the joint reads every frame; skip them while
the player or the gun is not fully there (loading, quitting). Proof: a quit with no exception burst in the log.`

## 3. Smaller lines, for whoever is on the part

- `[measured]` Re Scope VR: `spread-ray: WARNING -- our clean rotation is 0.056 deg from the game's own. The formula
  no longer matches.` in three logs (2026-11-01 01:55, 11-05 15:02, 11-06 00:32). Small, but the check says the
  formula drifted; worth one look at what changed on 11-01.
- `[measured]` Wolfsbane (ri3008), every run of 2026-11-06 22:46 to 11-07 00:15: `single rounds, magazine joint not
  found` and `reload: trigger refused until it is closed (#21500)`; also `drumrounds: the gun has no cartridgeJoint`.
  Probably as designed for a revolver; noted so the drum-hand work knows the log says so.
- `[measured]` Ghost Hand distances are back to centimetres (2026-11-06/07 reports: hands wander 3.3 to 7.5 cm), so
  item 1 of the 2026-11-05 drop (the 156 m gap) looks fixed `[n=5 reports]`. The same reports still say "the game's
  hand jumped 500 to 900 times while the controller was calm".
- `[measured]` Three "a system recenter" origin resets of 0.32 to 0.39 m (11-06 21:58, 23:49, 11-07 00:10): the headset
  recentered by the system, the mod followed it, as designed.
- `[measured]` re8-camfix `clonediff via.render.HazeFilter: main=false clone=false (component missing)`: neither camera
  has it, so nothing to copy; harmless.
