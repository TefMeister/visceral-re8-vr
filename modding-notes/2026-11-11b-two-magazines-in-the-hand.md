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

## Not built: the accuracy rule

"Gripping the gun with a magazine already in hand: 75%; with an empty hand: 100%, no spread." The lever is known
(`external-research/topics/2026-10-26-accuracy-from-movement-...`: replace or blend the bullet's rotation at the build
step, a native pre-hook; proven on the sniper rifle only). It is its own job with live shots, and one thing is Tefa's to
say first: what a handgun held in ONE hand should do (today: the game's own scatter).

## Code shape

- `reload.cpp` is now further past the 800-line mark (the board row for its split stands): fix later, that row.
- `visceral_re8_mag2.lua` and `visceral_re8_shell2.lua` share their maths and copy-making by copy: fix later (a shared
  module), board row.
