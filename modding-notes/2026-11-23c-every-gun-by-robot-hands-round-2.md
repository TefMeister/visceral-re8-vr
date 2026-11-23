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

## The other five slide pistols (carried through the window)

`tools/sim/carry.sh ri3046 <guns>`: the LEMI's pose of each reload stage sent again through the Hand Poser window with each gun
held at the same stage (M1911, V61, S.T.A.K.E, Samurai Edge, USM-AI): spare far (19), docked (17), pulled (18), out (16), and
without a spare "ready on magazine" and "magazine in hand". Sheets beside this note. On the Samurai Edge and the USM-AI the
magazine was already out at 70 % of the LEMI's pull length, so "pulling the magazine out" was not caught there: it falls back to
"magazine in hand" (not looked into: do those two have a shorter line, or does B drop the magazine straight out?).
The LEMI's slide grips (over the top, and from the left) were pictured and left as Tefa tuned them.

## b149, b150: the GM 79's next grenade (Tefa, this afternoon)

"grenade launcher also needs the mag1 and mag2 like the pistols, so grenade 2 can already be in hand while grenade 1 is still in
the launcher". Before: the pouch refused a round while the barrel was closed ("is closed: open it first") or loaded. Now
(`reload.cpp pouch_grab`, `breech.cpp insert_lt`): the pouch gives the GM 79's next round whatever the barrel's state; the
round never goes into a closed or occupied barrel by itself; with it in the hand, LT at the insert point breaks the barrel
open (that hand cannot take the front grip), the next LT swaps the spent case for it; LG let go throws the case. Run: fire,
pouch with the launcher closed, LT "barrel OPEN (LT at the insert point, the next round in the hand)", LT "swapped them", let
go, close at the front grip, fire `[verified-live 2026-11-23, robot, n=1]`. NOT run: a LIVE grenade still in the barrel (LT
should take it out to the carried ammo, then the round in the hand goes in). b150 = b149 without the testing switch
`hand_poser/blend_preview.json`.

## The loader's start-up hang (Tefa: "game is hung i think, only black")

One start of ten hung in REFramework's own start-up, before our code: the log ends in `Suspending <thread>` lines after
`Locking loader lock...` (62 paused, 17 resumed; a good start 76 and 76), the window black and not answering. Kept:
`dev-archive/recon/2026-11-23-startup-hang/`. `drive_real_slot.sh` spots it (the log still for 25 s with threads paused)
and starts once more by itself; KNOWN.md has the signature; the State-o-matiC rule is a row on the fault list.

## The long guns' hands, with the part brought to the middle of the picture (Tefa's idea, this afternoon)

"can you angle hands in front of the camera so you can have a look at whatever angle you need for long guns and just in
general". `tools/sim/frame.py <zone> yaw= pitch= roll= at=`: turns the gun as asked and slides it until the named grip zone
sits where wanted in the camera's view (it reads every zone in the camera's frame, `q_zonehv.lua`); `strokes.py` uses it for
each racking part, `magdock.sh` for a long gun's magazine. A charging handle on the gun's right side is looked at with
`view=right`.

- **F2: with LT held on the bolt the hand was flat and open above the bolt knob.** Fingers closed round it through the
  window ("slide" and "slide at the back"); picture `ri3042-f2-bolt-closed-grip.jpg`.
- **WCX, Dragoon, SYG-12: the same open hand at the charging handle**: the F2's closed grip sent to their "slide" pose
  (picture). Their "slide at the back" was not reached by the robot's pull (it keeps the pose in hand).
- **WCX, Dragoon, SYG-12: the hand "on the magazine" was drawn 15 cm in front of it, open.** Their docked wrist for the
  magazine was one untuned placeholder from build 32 (z 15 cm, y 3 cm, the same for all; the F2's had been tuned by Tefa:
  0.6 / 5.7 / 5.1). Set through the docked box from the F2's numbers (the SYG-12 2.2 cm up instead of 5.7), fingers curled
  ("ready on magazine"); picture.
- W870 and M1897: the pump is held from below, in both stages: looks right, not touched.
- NOT looked at: the Handcannon (drum, hammer, rounds), the Wolfsbane (one pose file: free), the GM 79 (no pose files), the
  shells in the hand, a long gun's magazine carried and going in, the right hand anywhere.
- Handcannon, pictured later (`ri3116-handcannon-hammer-and-drum.jpg`): with LG at the hammer ("handle") the left hand is drawn
  hanging UNDER the grip, fingers down, not on the hammer; at the drum it is mostly behind the gun. NOT changed (Tefa tuned
  this gun in the headset on 2026-10-27 / 11-01, and the robot's hold differs from a wearer's): to be looked at worn.

## Six views of a gun, and the zones by numbers (Tefa's second idea, this afternoon)

"can you also see guns from straight on, barrel pointed towards the camera, from bottom view and top view, so you have a clear
360 look at the weapon and all the hand poses on it, and where the grip zones start and end and overlap?"

- `tools/sim/turntable.py <ri id> <zone> <sheet> [lt] [long]`: the gun turned six ways (left, right, muzzle-on, from behind,
  from above, from below), each time with the named zone in the middle of the picture and the left hand taken onto it.
  First sheet: `ri3046-lemi-six-views-hand-on-magazine.jpg`. Not yet run on the other guns and stages.
- `tools/sim/zonemap.py` (the game running, the gun in hand): every zone's reach and, per pair, how far apart the centres are
  and how much the two balls overlap. ⚠️ `zones.json` cannot be used for this: it holds slider offsets, not places (my first
  table from it was wrong and was thrown away). Read live on 2026-11-23, build 151 `[measured]`:

```
gun 3046
   mag        reach 10.9 cm
   well       reach  9.0 cm
   slide      reach 12.0 cm
   slide-left reach 10.9 cm
   mag        / well         7.4 cm apart, overlap 12.5 cm (mag centre in well) (well centre in mag)
   slide      / slide-left   7.4 cm apart, overlap 15.5 cm (slide centre in slide-left) (slide-left centre in 
gun 3042
   mag        reach 14.0 cm
   well       reach 16.0 cm
   bolt       reach 14.0 cm
   grip       reach 12.8 cm
   mag        / well         0.2 cm apart, overlap 29.8 cm (mag centre in well) (well centre in mag)
   mag        / bolt        13.1 cm apart, overlap 14.9 cm (mag centre in bolt) (bolt centre in mag)
   well       / bolt        13.0 cm apart, overlap 17.0 cm (well centre in bolt) (bolt centre in well)
gun 3049
   mag        reach 12.0 cm
   well       reach 16.0 cm
   slide      reach 14.1 cm
   mag        / well         0.1 cm apart, overlap 27.9 cm (mag centre in well) (well centre in mag)
gun 3125
   mag        reach 12.0 cm
   well       reach 16.0 cm
   slide      reach 14.1 cm
   mag        / well         0.1 cm apart, overlap 27.9 cm (mag centre in well) (well centre in mag)
   mag        / slide       12.5 cm apart, overlap 13.6 cm (mag centre in slide)
   well       / slide       12.5 cm apart, overlap 17.6 cm (well centre in slide) (slide centre in well)
gun 3048
   mag        reach  9.0 cm
   well       reach  9.0 cm
   slide      reach 14.1 cm
   mag        / well         8.1 cm apart, overlap 9.9 cm (mag centre in well) (well centre in mag)
   mag        / slide       12.1 cm apart, overlap 11.0 cm (mag centre in slide)
   well       / slide        4.4 cm apart, overlap 18.7 cm (well centre in slide) (slide centre in well)
gun 3021
   well       reach  8.1 cm
   pump       reach  7.1 cm
gun 3036
   well       reach  9.4 cm
   pump       reach 13.3 cm
gun 3116
   handle     reach  8.0 cm
   drum       reach  6.0 cm
gun 3008
   handle     reach  8.0 cm
gun 3023
   grip       reach 10.0 cm
   insert     reach  7.0 cm
```

  (only the pairs where one zone's centre lies inside the other are listed; reach = the ball's radius.) Read with the rules in
  mind: the F2's bolt and magazine sit inside each other (the b146 rule decides: on an empty gun the nearer part wins, a rack
  due wins); **the Dragoon's magazine centre lies inside its charging-handle zone, and the SYG-12's well and charging handle
  are 4.4 cm apart**: the two guns where a hand meant for one part can be given the other. Pistols: the magazine and both
  slide zones do not reach each other (gaps 0.2 to 7 cm). Not changed today.

## Evening: "the 360 view for the robot", second pass (Tefa's name and brief)

Tefa: go over every gun again with the 360 view: mechanics, hands landing with LG, blends, no clipping, fingers close to the
gun, "right hand index finger on the trigger, right hand other 3 fingers gripping the handle. index finger moving with RT press",
and a new design for the grenade launcher (quoted in `breech.cpp`). What got done, and what did not.

### b152 / b153: the GM 79's latch, hand-moved barrel and gravity `[verified-live 2026-11-23, robot, n=2 to 3 per step]`

- **Right B is the thumb on the latch** ("add a thumb flick ... like wolfsbane does"): the thumb goes onto the latch and stays
  while B is held (at least 0.25 s), and flicks on release; only then the latch changes. Two right-hand spots for Hand Poser
  (5 "thumb on the latch", 6 "the latch flicked open"), both posed by numbers: the gun's `Lever` joint is the latch
  (0, 5.1, 6.5 cm in the gun's frame); the thumb's tip reaches to 1.9 cm behind it (a thumb is not longer).
- **Latch shut:** LG + LT on the barrel is refused ("the latch is shut: right B first"), the top hold (the insert point) is
  not offered, the pouch still gives the next round (b149).
- **Latch open:** a flick down lets the barrel fall open; LG + LT on the barrel (the front grip from below, or the top hold)
  moves it with the hand (the hand's way straight down against the gun hand, 12.6 cm for the whole swing); let go part way
  ("let go at 48%") it falls open by itself; pushed back up to shut, or a flick up, shuts it and the latch shuts with it.
  Firing is refused while the latch is open or the barrel hangs.
- The first cut measured the pull along the gun hand's own axis: nothing moved (that axis lies sideways in this hold). It is
  measured straight down now, as the fall is.
- b153 = b152 + the front grip kept again as a hold FROM BELOW (hand up under the barrel just ahead of the receiver, fingers
  curled: `tools/sim/gripkeep.py 90 0 90 6 8`), picture `ri3023-gm79-front-grip-from-below.jpg`. Three first tries left the
  hand flat beside the barrel. NOT done: a posed TOP hold, the `Lever` part turning with the flick, the thumb's poses judged
  from a good angle (the right-hand pictures of a long gun put the hand at the frame's edge).

### The right hand: a closed grip on every gun, and the trigger finger

- **Eight guns showed a flat, open right hand lying along the grip** (F2, WCX, Dragoon, SYG-12, W870, M1897, Handcannon,
  Wolfsbane; the GM 79 too): they had no right-hand pose, and the mod's "firm grip" only holds a hand after that gun's first
  shot of a session. The six pistols' kept grip (index in the guard, three fingers wrapped) sent to each through the window;
  pictures before and after beside this note. Coarse: one grip for every handle shape.
- **Hand Poser lost such a change**: a right-hand finger moved while the left hand was at one of its spots was filed in that
  spot's pose, which nothing reads. Fixed in the app (`Pose.cs SaveOtherHandToGun`).
- **The index finger bends on RT, every gun** (`righthand.cpp trigger_pull`, the last write of the frame): rest 32 / 15 / 42
  degrees, RT 36 / 35 / 52, released 32 / 15 / 42 `[measured on LEMI, F2, Handcannon, GM 79]`. It goes by time (0.07 s):
  **the loader gives no trigger travel**, pressed or not only (looked for on `vrmod` and on the game's pad device, whose
  `AnalogR` stays 0). Following the squeeze needs the loader changed.
  Three dead ends on the way, kept here so nobody repeats them: Hand Poser's own "trigger pulled" pose is computed but
  never shows in Village (some later write wins; not found which); a built pose in the script was wiped by its own
  two-second re-read; and BeginRendering comes twice a frame on Two Frame Sequential, so a bend applied to what stands doubled.
  The plugin's firm grip now leaves the index finger alone while RT is down and the thumb alone on the GM 79's latch.

### The left hand with the 360 view (`tools/sim/pass360.sh`)

- LEMI (magazine, slide, slide from the left): all three read as sensible holds from the right, below and front.
- **F2: the hand does not always land on the part aimed at.** Walked to the magazine's middle and to the front grip's, LG gave
  the bolt-from-the-left hold in two of three approaches (the zones sit inside each other: see the zone table above), and
  that hold ("slide from the left", "ready on slide from the left") was an open hand floating over the scope: given the closed
  grip. The landing itself is NOT fixed: it is the zone layout and the which-part-wins rule, on the board.
- NOT run with the 360 view: WCX, Dragoon, SYG-12, both shotguns, both revolvers, the other five pistols, every blend
  between stages, and any check for fingers passing through the gun (there is no measure for that yet: it is judged by eye).
- RE2 and RE3 were not gone over again this evening: their mechanics ran this afternoon, and their fingers are the game's
  animation until the build job on RE2's board is done.
