# 2026-11-23 (afternoon into evening, /lm, PC1, Fable): every gun by robot hands, round 2: the last two guns, b148, the hands

Carries on from `2026-11-23b-every-gun-by-robot-hands-on-the-desk-headset.md` (same rig: the real headset lying on the desk,
Two Frame Sequential, VR Bench's hands, nobody wearing it). Tefa is away; questions are asked once, at the end.

## The last two guns of the table

- **Wolfsbane (ri3008): passes** `[verified-live 2026-11-23, robot, n=1]`. Right B lifts the thumb and opens the cover; LG at
  the handle takes the gun into the left hand; RG at the left-hip pouch: "5 round(s) in the right hand"; the right hand held where
  the grip was docks at the cover (0.059 m; the dock is 10 cm round the place the right hand held the gun); RT one round in, LT
  turns the drum and drops a spent case, five times; "the drum is full": the hand goes back, the cover shuts; it fires.
  "Fire until empty counted 0" was `guncheck.py`: it counted `accuracy: shot`, which a revolver does not log (its drum went
  2 -> 1 -> 0). Fixed: the drum count going down and the GM 79's own line count as shots.
- **GM 79 (ri3023): passes** `[verified-live 2026-11-23, robot, n=1]`. The ammunition id that "refused" in October,
  1927571624, is the right one (the gun says so: `WeaponGunCore.getBulletItemID(0)`; index 1 = 1583016682, the flash rounds),
  and the save's case holds 4. The break opens ONLY with LG + LT on the front grip (praydog's two-handed grip), and this gun had
  no kept grip spot (`grip_spots.json` had 3036, 3042, 3046 only), so a hand that is not aiming could never open it. A spot was
  kept by robot (`grip keep 1` in `re_scope_cmd.txt`, the left controller 25 cm up the barrel: "(-0.185, 0.011, 0.232) in the
  right hand's frame"): coarse, Tefa's to redo in the headset (`grip unkeep` drops it). Then: open, LG at the pouch (1 round),
  the hand to the insert point: "the round went into the barrel", let go, close, fire: "the spent case stays in", open, LG + LT
  at the insert point: "the spent case is out, in the left hand", let go: thrown away.
  ⚠️ A LT press at the insert point right after the round went in takes the live round out again (by design; my first try did it).
- Seen in passing, not fixed: the log repeats `zones_open.json` / `grip.json` "parse error ... unexpected end of input" (empty
  files read as JSON), and the "trigger refused until it is closed" counter runs into the thousands while a breech is open.
- **Tefa, the same afternoon: "grenade launcher also needs the mag1 and mag2 like the pistols, so grenade 2 can already be in hand
  while grenade 1 is still in the launcher".** What exists: with a live round in the hand, LT at the open barrel's insert point
  swaps it with the spent case (`breech.cpp` "LT swapped them"). Not run by robot yet; see the board row.

## b148: the hand stays put at the magazine release and follows the pull (builds store reload/v0.1.0-b148)

- **Found by numbers** (`tools/sim/q_rel.lua`: the magazine in the left wrist's frame at every stage): at the B press the wrist
  flipped to a quite different angle on the magazine, and flipped again when the magazine left the grip. Cause
  `[inferred-static, then verified-live]`: `reload.cpp hand_on_mag_pose` undid only the built-in hold (`MAG_HOLD`), not this
  gun's MAGAZINE IN HAND box, and `dockpose.cpp` dropped the docked spot's numbers at the same instant.
- **Now:** while the magazine is on the grip's line (or being pushed home) the left hand goes from where it was DOCKED on the
  seated magazine (noted each frame it sits there) to the exact hold it has once the magazine is out, by how far out it is.
  Run: the magazine in the wrist is identical before and after B; 14 / 42 / 76 % out moves steadily to the in-hand hold; out:
  no step `[verified-live 2026-11-23, robot, the LEMI's spare swap, n=2 runs]`.
- **The pull distance is handed to Hand Poser** (bridge slot 279 = 1 + how far out, 0 = not on the line; the Lua array is 280
  long now: the DLL and `visceral_re8_bridge.lua` go in together). `hand_poser.lua` shows the left hand between the seated
  pose and the spot's own by that distance. On a pistol `mag_out`'s finger clip now plays on the RIGHT hand only (it silenced
  Hand Poser's left hand for 1.4 s, about as long as a pull).
- Not worn. What Tefa should feel for: the pull without the finger clip on the left hand.

## Hand Poser and the picture method

- Hand Poser (hand-poser-vr fa2bc43, installed): the LEFT HAND, DOCKED box takes input from outside (`"dock"`), every answer
  says what its sliders show. `tools/sim/pose.py dock.y=1.5`, `pose.py dock`.
- **Pictures that show the hand:** the jacket hides it from every angle the desk headset has. `q_sleeve.lua` (testing only)
  switches the body mesh's materials off (`rv.py "E.body=false return 1"` then `rv.py -f q_sleeve.lua`); the hands are their
  own meshes and stay. With `SNAP_GAMMA=0.55` and a crop, the gun's RIGHT side (`hv` yaw -90) shows the left fingers at the grip.
- **Fingers by numbers:** `q_wrist.lua` (the hand's joints and fingertips in the wrist's frame, cm: x toward the fingers, -y out
  of the palm, +z the thumb's side), `q_rel.lua` / `q_hand.lua` (magazines against the wrist / the hand against the magazines),
  `geo.py`, and `solve.py` (moves named joint angles THROUGH the window until named fingertips sit at wanted places; about a
  minute per finger). `hold_at.py <stage>` brings the swap to one stage and stays; `stages.py` pictures all of it; `reseat.py`
  starts clean (my first try at stage poses overwrote the LEMI's plain "magazine in hand" pose because the magazine was still out
  from the step before: put back from b148's copy through the window).
- The gun's Magazine joint sits at the gun's root when seated, raked 18 degrees; the magazine runs about 1 cm above to 9.5 cm
  below it along its own y `[inferred from pictures]`.

## The LEMI's spare swap, as posed (coarse; sheet `2026-11-23c-hands-sheets/ri3046-lemi-spare-swap.jpg`)

- The spare's place (one set for every gun, SPARE MAGAZINE box): x 5.8, y -1.1, z -5.5, rz -19.6, ry -11.9, rx -58.0 (was x 3):
  it stands beside the grip's front, leaning forward, in the web between thumb and index, instead of hanging under the wrist.
- Thumb round the spare's outside in every spare stage (solved: within 1 cm of the wanted place); the docked stage keeps the
  curled fingers of this morning; "pulling the magazine out" and "two magazines in hand" close index to pinky round the old
  magazine (M -45 / -105 / -45 and so on); "spare in hand, magazine still in the gun" has the other fingers half open.
- NOT judged: whether the thumb really touches the spare (its real size is a guess), the look from the wearer's eye, anything
  about feel. Tefa's "hand travels on to the bottom of mag1" is the docked spot's own glide (unchanged).
