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

11:39, the second try `[measured 2026-10-25]`: none of the five spheres loaded. setMesh was handed the bare resource from
`sdk.create_resource`, and the game read garbage inside setMesh (access violation, caught by REFramework, 30 times, no crash; the
game was then closed normally at 11:42). Mesh.setMesh and set_Material take a resource HOLDER (`res:create_holder(
"via.render.MeshResourceHolder")` / `"via.render.MeshMaterialResourceHolder"`). Fixed (installed 11:47), and a sphere path that
fails once is never tried again. Andyalpa's holster visuals pass the bare resource too on their path-created branch.

11:48-11:56: the holder fix worked (`sphere mesh: vfx/mesh/mesh_primitive/sphere_mediumpolygon.mesh`, no exceptions), but still no
spheres (Tefa: "i still don't see any spheres, do any of these windows have to be in focus?"; no window needs focus: the game
script draws them and the windows only write files). `[measured 2026-10-25]` the spheres were made at the title screen (show was
on) and the save's scene change destroyed them: `findGameObject("visceral_re8_zone_0")` through the REFramework MCP found none, and
nothing made them again. Also the model's box could not be read at spawn ("half size nil"), so the size was a guess. Fixed
(installed 11:56): a dead sphere has all made again (at most once a second), the size is measured from the drawn sphere's world
box (guess 0.5 m half until then), and every 5 s the log says where each sphere is, how big, shown or not, and the look.

Also found: the Hand Poser's buttons did nothing when clicked through Window View (Tefa: "clicking on any of these does not bring
up the sliders"). Window View posts mouse-down / mouse-up to the control; the stock WinForms button only clicks when it is also
the topmost window at that desktop spot (WindowFromPoint), and a window used in the headset sits behind others on the desktop.
Skin.cs SkinButton / SkinCheckBox / SkinRadioButton click on a posted down + up themselves when the stock way did not; tested with
a topmost window covering the button: the click added all 15 left-finger joints. Used in Hand Poser and Grab Zones.

## 12:15, third sphere wear: still nothing; the test ball

Tefa: "spheres still did not show up, i went through all the sphere designs and nothing showed". The 5 s log line
`[measured 2026-10-25]` had all four spheres SHOWN at the gun (30.3, -29.6, 66.6) at the right size (half 0.566 m measured,
scale 0.21 for the 12 cm magazine zone): the objects existed and drew nothing. An RE Engine mesh draws only with a material whose
names match its own slots; the shared effect materials never did. Village ships a development test ball WITH its own material:
`environment/props/resource/sm0x/sm00_111_testball/sm00_111_testball_00.mesh` + `.mdf2` (found in RE8_STM_Release.list by
looking for round meshes with a same-named mdf2; two balloons the same way as fall-backs). Installed 12:48 (backup
`_backup-2026-10-25-1248-before-visceral-re8-deploy`); the look list starts with "its own" (the mesh's own material), and the
saved look moved to a new key so an old pick does not carry over. Unseen.


## 13:55 Three more findings from the fifth wear (Fable)

**The spheres, fifth try.** Worn 13:20-13:37 with the test ball switched fully on (the log read back: mesh enabled, draw by
default, render output 15, the object draws), SHOWN at the gun at the right size, and still nothing in the headset. Sixth try:
the first choice is now a small copy of the gun in hand, taken from the held weapon's own mesh and material holders, which is
how Andyalpa's holster visuals draw (and they draw). Made only once a gun is in hand. If even that is unseen, the mesh was
never the fault; the spawn folder or the transform parent is next.

**The hand jumping to the forestock.** Tefa, reaching for the rifle's bolt: "whatever i did, it kept jumping onto the front
handle". The log had `[re8-grip] stacked grip TAKEN (3 cm above, 10 cm to the side)` at every jump, with `our_grip=false`: not
the grip take at all, but the scope mod's stacked-hands gesture (LG held with the left controller 3-35 cm above and within
12 cm beside the right one draws the hand on the captured forestock spot). The bolt sits exactly there, and the rack measures
the DRAWN hand, which the stacked grip had just moved to the forestock, so the bolt was "rarely" taken. Off in Visceral RE8's
copy of the grip script; `grip stacked 1` turns it on again.

**The front grip is a zone.** zones.h GRIP (bridge slots 136-140): smooth.cpp publishes the gun's kept grip spot as a world
sphere each frame, moved by zones.json "grip" in the gun's axes, as big as the take distance (10 cm). The grip script takes
the grip when the left controller is inside it, and the socket it then holds is the sphere's centre in the right hand's
frame. Grab Zones has a FRONT GRIP box for it. Before this the take was measured against the kept socket in the un-steered
controller frame, which nobody could see.

**The crash at 13:37:55.** Inside the game's app.WeaponCore.requestMotion (from app.PlayerMotionController.update), RCX
0x100000000, one second after a stacked take, after a bolt hold and a free -> slide -> free hand change. Dump and log kept in
`D:\RE Village REFramework builds\logs\` (reframework_crash-2026-10-25-1337.dmp, re2_framework_log-2026-10-25-1400-crash.txt).


## 16:30 The two crashes of the day, read from the logs (Fable)

Both crashes (13:37:55 and 14:33:47) are the same event, step for step:

1. A Lua call of `app.PlayerWeaponChange.equipWeapon` throws an access violation inside the game, at the same instruction both
   times (re8.exe+0x3386b65); REFramework catches it and carries on. One millisecond later a Lua call of
   `app.EquipController.equipWeapon` throws too (the second time through a garbage pointer, RIP on the heap).
2. The weapon in hand becomes an inventory item the plugin does not know: `ri5003_Inventory` the first time, `ri5052_Inventory`
   the second (no joints, no gun transform, not in `weapon-ids.md`; neither is a knife, those are ri3022 / ri3044). Neither item
   was in hand at any other moment today.
3. 1.5 s later `app.PlayerSecondUpdater.update -> app.PlayerMotionController.update -> app.WeaponCore.requestMotion` jumps through
   that object's type record and lands in `.data` (re8.exe+0x94676a0, in the .data section; RIP == RAX both times) and the game
   dies. Both crashes had the rifle with a rack pending, and both followed a hand reload shortly before; that is the moment Tefa
   also tied them to ("taking the mag out with LG does something to make it crash shortly after the reload").

The caller is Andyalpa's holster script (our copy, `re8_vr_holster.lua`): `tick_native_weapon_change_unstick` watches the
game's own requested item (`PlayerWeaponChange.get_RequestedItem`, a D-pad / quick-slot request; in Visceral RE8 the D-pad is the
right stick while the left thumb rests on the thumb rest) and, when the native swap has not finished within 0.2 s, "finishes" it
in Lua: `native_equip -> equipWeapon`. Its `get_item_weapon` hands back ANY `app.ItemCore` as "the weapon", so an item that is
no gun and no knife reaches `equipWeapon(app.WeaponCore)`. Why the native swap stalls at that moment is not known (our held hands
and the pending rack are the suspects); it does not matter for the fix.

Two guards, both installed 16:30 (plugin rebuilt, `src/equipguard.cpp`; the holster script):

- **Plugin:** `app.PlayerWeaponChange.equipWeapon`, `app.EquipController.equipWeapon` and `EquipController.set_equipWeaponRight`
  are hooked; a call that returns into REFramework's module (a script, told apart as nodock.cpp does) with an object that is not an
  `app.WeaponCore` that is a gun the plugin knows or a knife (`app.WeaponMeleeCore`) is skipped and logged with the object's name
  and type (`equip guard: a script asked ... REFUSED`). The game's own calls are never touched.
- **Holster script:** the stalled-swap finish only runs for a gun or a knife (`classify_item_core`); anything else is left to the
  game and said once in the log (`stalled swap to ri5052 NOT finished by hand`).

What proves it: the next time those lines appear and the game keeps running. If the game crashes with no such line, the reading
is wrong. Still to learn: what ri5003 / ri5052 are (the guard's log line names their type).
