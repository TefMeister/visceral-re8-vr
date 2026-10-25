# 2026-10-25b: the bolt stole the hand (the last wear's log, read; the fixes built and installed)

No game running. The log of the 03:48 build's wear (kept as `D:\RE Village REFramework builds\logs\re2_framework_log-2026-10-25-0354-last-wear.txt`)
explains all four of Tefa's 04:00 complaints. Build b5d20f59, installed 08:55 (backup `_backup-2026-10-25-0855-before-visceral-re8-deploy`).

## What the log showed `[measured 2026-10-25]`

1. **"The mag jumps back in after I take it out."** Every pull-out was followed within 0.1 s by
   `the magazine is clear of the well (0.126 m)` and, the same frame, `insert at 0.126 m (need 0.16)`. The clear distance
   (`INSERT_CLEAR_M` 0.12) lay INSIDE the long gun's insert distance (`DOCK_ITEM_M` 0.16), so "clear" and "back in" were one
   moment. Twelve pull-outs in 11 s at 03:53, each re-seated at once (Tefa hammering LT).
2. **"Hand still gripped on the rifle grip handle alongside the right hand."** Not the grip script: it took the grip ONCE, on the
   forestock (socket 0.39 m from the right hand, so the 25 cm long-gun rule held), and the game's own dock answered 0 asks (off).
   It was the RACK: the F2's bolt joint (its "Slide", gun-local 0, 0.088, 0.018) sits 13 cm from the magazine joint (0, 0.021,
   0.131). The bolt zone was 14 cm around that joint measured from the CONTROLLER, which sits ~15 cm behind the drawn hand, while
   the magazine zone is 12 cm measured from the drawn hand (the left IK target). So a reach for the magazine that missed by a few
   cm (0.122-0.18 m, 03:52:14-32) was taken by the bolt ("HAND ON" at 0.140 from the joint), and the hand was held up at the bolt,
   beside the right hand.
3. **"Very hard to get it to dock on the mag."** The grabs that worked measured 0.080, 0.111, 0.102, 0.100, 0.104, 0.112, 0.118 m
   (drawn hand to magazine joint): 0.12 is the right zone. The misses were the bolt trap above: once the bolt held the hand, the
   drawn hand WAS at the bolt, 0.13-0.18 m from the magazine, so every further LG press missed until LG was let go.
4. **"The bolt activation area is too large."** The same 14 cm controller-measured zone.

## Built `[compile-verified 2026-10-25]`

- `settings.h`: `INSERT_CLEAR_MARGIN_M` 0.10 replaces `INSERT_CLEAR_M`; `RACK_BOLT_GRAB_M` 0.09 new.
- `reload.cpp` hand_checks: a pulled-out magazine is clear only past the insert distance + 0.10 (long gun 0.26 m, pistol 0.34 m);
  the log line says both numbers.
- `rack.cpp`: the bolt is measured from the drawn left hand (the IK target, the magazine's point) with the 9 cm radius; the slide
  and pump keep the controller and 14 cm (Tefa: "shotgun is fine now!", untouched). The near log line names the joint and the
  point measured from.
- Nothing changed in the grip script or nodock: they did their job.

## For the next wear

Rifle: LG on the magazine (within 12 cm), LT: it comes out and STAYS out while the hand is near the well; it goes back in only
after the hand has been 26 cm away first (log `clear of the well (... needed 0.26)`). Reaching for the magazine and missing no
longer puts the hand on the bolt; the bolt takes only within 9 cm of its handle (log `from the bolt joint (need 0.09, the drawn
hand)`). The hand next to the right hand should be gone. Not yet looked at: the pistol rules from mod-ideas (board row).

## 09:20, Tefa: "can this be set so that LT must be pressed again for it to go back in, that would solve this problem for good"

Agreed and built (a3bf6318, installed 09:40, backup `_backup-2026-10-25-0940-before-visceral-re8-deploy`). The 26 cm clear rule is
gone. A magazine pulled out by hand now sits at the well, however close, until a fresh LT press while it is at the gun (`INSERT_NEEDS_LT`;
the pull-out's own press cannot count: 0.25 s wait, `INSERT_LT_MIN_SEC`). Log: `the pulled-out magazine is at the well (...): press LT
to seat it` every 2 s while it waits, then `LT pressed at the well: the pulled-out magazine goes back in`. A fresh magazine from the
pouch still seats by itself when brought to the gun (unchanged; LT there too if Tefa wants it).

## 09:45 wear (build a3bf6318), Tefa's words, and the log

> the mechanics of it work now, but the activation points are broken ... hand still gripping the grip of the rifle [a 03:31
> screenshot] ... this is the distance from where the hand jumped to the front handle point, instead of gripping the mag -
> then after trying different points, the mag finally came out after the left hand was gripping the grip handle, then LT took
> out the mag, LT again put it back in and after that, LG would not grip the front of the rifle unless the weapon was turned
> almost sideways to the left.

Log (`logs/re2_framework_log-2026-10-25-0950-lt-seat-test.txt`) `[measured 2026-10-25]`:
- **LT to seat works**: `LT pressed at the well: the pulled-out magazine goes back in`, `insert at 0.063 m`. The pulled-out
  magazine waited at the well (`press LT to seat it` at 0.046-0.157 m) and never re-seated by itself.
- **The hand jumping to the front handle** (09:44:52): LG pressed with the hand 0.294 m from the magazine; the grip script took
  the forestock (`grip taken #1 (our own dock on the frozen socket)`), then `the ANIMATION has moved the socket 87.62 deg under
  the held grip -- IGNORED, the gun does not move`, let go 2 s later ("moved 5.0 cm and 13 deg"). The magazine grabs that worked:
  0.098, 0.118, 0.107, 0.109, 0.119, 0.065, 0.102 m; the misses 0.122-0.29 m. The bolt took the hand once, at 0.089 m
  (hand 0.22 m from the magazine): correct.
- **"Gripping the grip handle" while holding the magazine** (image 3): that is the magazine HOLD pose (`MAG_HOLD`, RE7's
  handgun numbers) drawing the hand low and behind the well on the rifle; the grab itself happened at 0.10 m. A Village rifle
  hold needs posing. `[hypothesis]`
- **"LG would not grip the front unless the gun was turned sideways"** (09:45:20): `grip taken #2`, then `the ANIMATION has moved
  the socket 86-109 deg ... IGNORED` every few frames and `grip let go ... 26 deg (limit 25)`. The grip script's LIVE socket (the
  game animation's left hand against the right) is ~90-110 deg off the kept one: with the game's dock off (nodock answers the
  left-hand joint ask with the root), the animation's left hand is no longer on the gun, so the live socket is garbage, the
  keep-test fails and the take is only accepted in the one pose where the garbage happens to line up `[hypothesis]`. Fable's
  job: the grip script must not read the live socket while nodock is on (use the kept socket alone, or the plugin's bridge).

## The zone editor, built 10:04 (build 34ec3f65), UNWORN

Tefa: "is there any way I can visibly set them, how big they are, where they are on the gun ... a helper program that translates
numbers into actual sliders and movable areas that ride the gun all the time". Built:
- `src/zones.cpp` + `zones.h`: every grab zone (the magazine grab, the well, the slide / pump / bolt) is an offset from its joint in
  the gun's axes plus a radius, read from `reframework/data/visceral_re8/zones.json` (per gun over "default" over settings.h),
  re-read the moment the menu saves (bridge slot 115). reload.cpp and rack.cpp test against these. Every frame the plugin publishes
  each zone's world centre and radius, and the point the hand is measured from (bridge slots 116-135, N = 136).
- `lua/visceral_re8_zones.lua`: menu "Visceral RE8 grab zones": "Show the zones on the gun" draws a ball per zone riding the gun
  (a game mesh scaled to the radius: our own sphere mesh when one ships at `natives/stm/visceral_re8/zone_sphere.mesh`, else the
  First Aid Med model Andyalpa's visuals already spawn); per zone, live "hand N cm away, needs R", three position sliders
  (forward / up / right, cm, in the gun's axes) and a size slider; edits this gun's zones or the defaults; "Forget" buttons.
  A "ball model size fix" slider sets the model's half size (the Med model's is a guess, 5 cm).
- Not in it yet: the forestock grip zone (the grip script's own, `GRIP_DOCK_M` 10 cm around the kept socket) and the magazine
  HOLD pose. Both could join the same file.

## 10:30, the Grab Zones window (Tefa: "can you make the gun grip activation sliders a separate thing just like you did with the hand poser, so i can use it with Window View")

Built in `dev-archive/native/zones-app/` (C#, like Hand Poser), installed on the home PC with a desktop icon "Grab Zones".
Same sliders as the in-game menu, large type, − / + buttons for half-centimetre steps, live "hand N cm away, needs R" per zone
(green inside), THIS GUN / ALL GUNS, SHOW THE BALLS, RESET per zone, FORGET (two clicks). It writes zones.json; the plugin now
also re-reads it when its write time changes (every 20 frames, `ZONE_FILE_CHECK_FRAMES`), and the zones script writes
`zones_state.json` four times a second, re-reads zones.json twice a second, and takes "show the balls" from the file.
`[verified-numerically 2026-10-25]` self-test 14/14 PASS; against a stand-in game folder the window named the F2 Rifle, showed
the live distances, and two clicks on "+" wrote `"3042":{"mag":{"r":0.13}}` with `"show":true`. Not yet run beside the real game.
Plugin e362d3fb installed 10:33 (backup `_backup-2026-10-25-1033-before-visceral-re8-deploy`).

## 11:30, first wear of the zone editor (Tefa: "i can't actually see any points on the gun")

The window connected, the live distances moved and a slider moved the zone (zones.json re-read), but no sphere drew
`[measured 2026-10-25]`: the script took `visceral_re8/zone_sphere.mesh` (never made) because `sdk.create_resource` hands back an
object even for a missing file, then `via.render.Mesh.setMesh` threw inside the game four times (`Exception thrown in
REMethodDefinition::invoke for via.render.Mesh.setMesh`, 11:28:48), so all four spheres were empty. Fixed (installed 11:34,
backup `_backup-2026-10-25-1134-before-visceral-re8-deploy`): the candidates are Village's own primitive spheres from its file
list (`vfx/mesh/mesh_primitive/sphere_mediumpolygon.mesh` first), a mesh counts only once `getMesh` gives it back, its half size
is measured from `get_ModelLocalAABB` so a sphere is exactly its zone's size, and "SPHERE LOOK" (in-game menu and the Grab Zones
window) cycles Village's shared effect materials (`vfx/mesh/mesh_common_mtr`: light pillar, glass, liquid, mold, axis, dev test,
none) because which one shows on these meshes is not known `[hypothesis]`. Needs a "Reset scripts" in REFramework to load.
