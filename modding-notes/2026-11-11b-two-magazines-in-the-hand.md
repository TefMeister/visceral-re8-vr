# Two magazines in the left hand: a handgun reloaded without being empty (2026-11-11, PC1, Fable)

Tefa, 2026-11-11 (at work, by remote desktop): *"with handguns, to be able to take out a mag from pouch when a mag is still in
the handgun. idea is to have a spare mag taken out with LG and LG held bringing my hand to the pistol, it docks under the mag
with a spare mag in hand. then when i press B, i can pull out the mag from the gun and have now 2 mags in hand. once the mag
that was in the gun is fully out, pressing LT puts the new spare mag in the chamber without the need to push it in by hand -
the hand just has to follow the mag that is being inserted, not leaving the left hand docked on the bottom of the new inserted
mag, with the old mag still being held with LG. once LG is released and the old mag is either dropped or put into any of the
holster zones on the body (something we still have to do, the mag can either be dropped or if placed into any of the holster
zones in the body, it just dissapears from hand without dropping down) - then i can use the hand normally ... downside has to
be that gripping the gun with mag already in hand, lowers the accuracy to 75%, while gripping the gun with an empty hand has
100% no bullet spread accuracy"*.

Build b113. `src/twomag.h` has the design; the steps live in `reload.cpp`; the extra magazine is drawn by
`lua/visceral_re8_mag2.lua`.

## What is built

| Step | What happens | Where |
| --- | --- | --- |
| LG at the pouch, a handgun's magazine still seated | a spare in the hand (refused with nothing carried) | `pouch_grab` |
| LG held to the seated magazine | the hand docks on it (no fresh LG press needed); taken 3 zone radii away it undocks | `grab_frame` |
| right B | the gun's magazine comes out along the grip into the hand, as before: two in the hand | `pull_out`, the rail |
| LT, the held magazine within 0.25 m of the well | the swap: the spare travels from the hand to the bottom of the grip and up it by itself (0.19 s), the hand stays the controller's and keeps the old magazine | `swap_in`, `pose_joint` INSERT |
| LG let go with the old magazine | it drops (the thrown-magazine copy, as full as its own rounds), or in a holster spot it is put away | `twomag_frame` |
| LG let go with only the spare | back in the pouch | `twomag_frame` |
| the gun's magazine dropped to the floor while a spare is held (B away from the gun) | the spare becomes the ordinary magazine in the hand and seats at the well by itself | `twomag_frame` |
| any magazine let go in a holster spot | put away instead of dropped (also the ordinary one) | `hand_checks` |

The ammo is the ordinary reload's: the old magazine's rounds stay counted, the new one is topped up from the carried ammo.

How it is drawn: the gun has one magazine joint. Whichever magazine is NOT the gun's joint is a copy of the gun's mesh with
its Body joint 100 m down and its Magazine joint written into the hand (the second shotgun shell's way). Before the swap the
copy is the spare, in the hand's second place (3 cm along the magazine's own x: a first guess); at the swap the joint
becomes the new magazine going in and the copy becomes the old one in the first place. The copy shows only the magazine
part, the second magazine part and the "vanish when empty" parts (the rounds, on only when it holds any).

## What was seen

- Flat `[verified-live 2026-11-11, flat, n=1, LEMI]`: the copy alone in front of the camera, loaded (a round on top) and
  empty; the spare's place 3 cm from the hold; the Lua's "drawn here" numbers come back to the plugin.
- OpenXR Simulator + VR Bench `[verified-live 2026-11-11, simulator, n=2 full runs, LEMI]` (`tools/sim/twomag_test.py`):
  spare taken with 9 of 12 loaded; docked 0.003 m from the magazine; B onto the grip's line; out of the bottom after 10 cm;
  LT refused at 0.439 m, done at 0.065 m; seated; `new magazine: 12 rounds (3 from the carried ammo)`; the old one stays
  with LG and drops as a thrown copy with its 8 rounds' look; a lone spare goes back to the pouch.
- NOT seen: any of it in the headset; where the two magazines sit in the palm (the simulator draws the hands out of view);
  the holster put-away (log path only); any handgun but the LEMI.

## Found on the way

- `bridge::has()` calls any value over 499 "no value": it is for room numbers, never for a frame stamp. The first build
  never used the Lua's place for the spare because of it.
- Mirroring every part the gun shows drew the LEMI's suppressor on the copy: it does not hang under Body. The copy now
  shows only the named magazine parts.
- On the simulator the game pauses when its window is not in front and the hands then keep stale poses: a whole test run
  was wasted on that; `twomag_test.py` brings the window forward before every pose.
- On the simulator the gun is drawn about 0.4 m below and 0.3 m behind the right controller, so a fresh magazine cannot be
  seated at the default robot pose ("not in front of you at gun height"); a run that drops the magazine needs a game restart.

## The accuracy rule (b114, `src/accuracy.h`)

Tefa, 2026-11-11, later: *"one handed running is 30%, walking is 50%, standing still is 75%, extra mag in hand, running is
40%, walking is 65%, standing still is 85%, both hands on the gun - LG docked on the mag, running is 50%, walking 80%,
standing still 100%"*.

- Where: the scope project's lever, now a dial. `app.WeaponGunCore.createBullet` gives the ray, `createBulletImple` is
  handed the scattered rotation; ours replaces it with the clean aim turned by a random angle inside a cone of
  (100 - accuracy)% of `ACC_CONE_DEG` (5 degrees, a first guess). The lever works on a handgun too
  `[verified-live 2026-11-11, simulator, n=12 shots, LEMI]`: it had been proven on the sniper rifle only.
- Which guns: magazine-fed handguns in VR. Everything else keeps the game's own scatter.
- The hold: both hands = docked on the magazine, or the game's own two-handed grip, or LG held within 12 cm of the well;
  "a magazine in it" = the same with any magazine in the left hand; else one hand. A magazine merely carried, away from
  the gun, is one hand (my reading of "gripping the gun with mag already in hand").
- The movement: the player's speed over the ground, smoothed 0.2 s: under 0.30 m/s still, under 2.60 walking, else
  running. The game's own speeds `[measured 2026-11-11, app.PlayerMovement fields read live]`: walking 1.66 m/s, running
  3.43; hurt 1.40 / 2.30 (a hurt run counts as walking).
- Seen on the simulator `[verified-live 2026-11-11, simulator + VR Bench, n=3 shots each]` (`tools/sim/accuracy_test.py`):
  one hand still 75% (bullets 0.89-1.10 deg off, cone 1.25); LG on the magazine 100% (0.00 deg, three of three, where the
  game's own would have been 1.34-3.39); a spare docked 85% (0.26-0.64 of 0.75); walking 50% (2.45 of 2.50, n=1: the player
  walked into a fence). The LEMI's own scatter in VR on those shots: 1.06 to 3.39 deg.
- NOT seen: a running shot (the magazine was empty by then; the class is the same code as walking); how 5 degrees FEELS;
  the old-magazine-in-hand case near the gun; any other handgun.

## Code shape

- `reload.cpp` is now further past the 800-line mark (the board row for its split stands): fix later, that row.
- `visceral_re8_mag2.lua` and `visceral_re8_shell2.lua` share their maths and copy-making by copy: fix later (a shared
  module), board row.
