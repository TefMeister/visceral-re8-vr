# 2026-10-18 — Manual reloads, slide rack and pump, moved over from Visceral RE7

## Why

The same evening Tefa asked for a C++ RE7 version (recoil, manual reloads, holster spots) from Andyalpa's RE7 VR
Reloaded, then: *"ah crap, i forgot to tell you to that for re8 village ... i want to do Visceral of re7 when a good half
a year has passed. please save the re7 build only on this pc and in the private re7 repo on github, then please see if
you can get the re village weapon id's and port over the re7 reloading systems"*. RE7 is parked in its private repo; its
reload, rack and hand-state code now runs in Visceral RE8. Village already has holsters (Andyalpa's Hands Off, still
Lua), so the RE2-style holster spots were not brought over.

## What came over, and what changed for Village

| File | From | Village change |
| --- | --- | --- |
| `reload.cpp` | RE7 (itself RE2's) | where a magazine / shell goes in is measured from the controllers in the room (at the gun hand for pistols, 0.20 m ahead along the barrel for long guns), because Village's gun parts are not known; the magazine joint (`_04`, a guess) is only animated if it exists |
| `rack.cpp` | RE7 / RE2 | the left hand's place on the gun is captured from the left IK target at the moment it takes hold, then held there relative to the gun hand and slid back with the pull; grab test = the left controller on the gun line (RE2 b162's pump test, every gun); slide joint `_01` moved only if it exists |
| `ik.cpp` | RE7 | takes over recoil's `app.AnimIK2Bone.calc` hook; recoil runs first, then the rack |
| `handstate.cpp` | RE7 | `reframework/data/visceral_re8/hand_state.json`; also sets `__visceral_reload_busy` |
| `weapons.cpp` | new | 29 ids (`weapon-ids.md`), how each reloads; unknown ids to `weapon_ids.json` |
| `player.cpp` | extended | the ammo calls (below), `type_probe.txt` |
| `bridge` | extended | 96 slots: controller turns, the camera, Andyalpa's ammo spot, the pose switch |
| `re8_vr.lua` (ours) | 2 lines | the block pose is skipped while `__visceral_reload_busy` (a reload in the left hand) |
| `recoil.cpp` | 4 lines | no kick queued while the magazine is out or a rack is due; no support-hand follow while the hand is on the slide. The numeric test still matches Andyalpa's Lua (480 frames, worst 3.19e-6) `[verified-numerically 2026-10-18]` |

**The ammo pouch is Andyalpa's own left-hip "ammo_left" spot** (`re8_vr_holster.lua`): it buzzes and sets
`__vr_in_ammo_holster_zone`, and no file of his pack ever acted on it — it was waiting for a reload. Our own left-hip
spot (RE2's position) counts too, in case his is switched off.

## The unknown: Village's ammo calls

No Village type list exists on our side and none is public (web + GitHub code search, 2026-10-18). Andyalpa's Village
files only show `getBulletNum`, `get_isLoadNumInfinity`, `get_isLoadNumUnderOne`, `get_isMagazineEmpty`, and his Village
holster uses RE7's inventory calls (`getQuickSlotItem`, `applyQuickSlot`, `setQuickSlot`, `get_ItemSlotManager`). So
each ammo call is tried from a short list with RE7's name first (`player.h`), and the first time a gun is held the plugin
writes **`reframework/data/visceral_re8/type_probe.txt`**: every method and field of the gun, the player gun, the
inventory and `app.InventoryManager`. The log says which names answered (`ammo: loaded = ...`) or were NOT FOUND.
`[hypothesis]` until that first start. If the setter is missing, right B does nothing and says why; the carried-ammo
calls missing = a new magazine only gets back its own rounds.

The game's own reload is skipped only if a `tryReload` / `requestReload` exists on the player gun or WeaponGunCore
(logged); otherwise it stays on beside ours until the probe names the real one.

## Controls (as Visceral RE2 / RE7)

- **Right B** — magazine out. **Left grip at the left hip** — a magazine (or one shell / grenade / round) into the left
  hand. **Bring it to the gun** — in. Let go of the left grip with it in hand — dropped.
- **Empty gun / rack needed:** left grip with the left hand on the gun line takes hold; LT; pull back along the gun;
  let go of the left grip = forward, chambered. **Pump:** left grip + LT on the barrel; pull back; let go of LT.
- **REFramework menu → "Visceral RE8 reload":** the left hand's state and **"Hold this pose"** (the magazine stays in the
  hand, the hand stays on the gun) for posing the fingers with Hand Poser.

## Installed

Home PC, 2026-10-18 21:59, plugin `63dd732e` `[compile-verified 2026-10-18]`, never run with this code. Backup:
`D:/RE Village REFramework builds/_backup-2026-10-18-2159-before-visceral-re8-deploy/` (the six scripts it "updated"
besides ours differed only in line endings: checked, nothing lost).

## Later the same evening: the first starts (Tefa: "go") -- the ammo calls are known now

Three flat starts to the title screen, closed with a normal close each time (no gun held, no save loaded):

- **Everything hooks** `[verified-live 2026-10-18, n=3]`: `reload: hooked app.PlayerGun.tryReload` and
  `app.PlayerGunPl2001.tryReload` (Chris) -- the game's own reload is skipped for our guns; `ik: hooked
  app.AnimIK2Bone.calc`; recoil, haptics, `BRIDGE ATTACHED`.
- **`type_probe.txt` gave Village's ammo model** (written from the type database at the title screen, so no gun is
  needed any more). A gun is an item: its record (`ItemCore.get_work` -> `app.ItemCore.InstanceWork`) holds the loaded
  rounds as `includeStackSize` (`includeStackSizeSub` for the second ammo kind, chosen by `get_usingBulletIndex`), the
  most it holds is `getMaxIncludeStackSize`, the carried rounds are `Inventory.getTotalStackSize(bullet item id, bool,
  bool)` with `WeaponGunCore.getBulletItemID()`. The gun itself has `reload()`, `reload(int)`, `reloadNoReduceBullet(int)`,
  `forceFullReload()`, and `switchMagazineDisp(bool)` / `resetMagazineDisp()` plus `NormalMagazinePartsNo` (the magazine
  is a mesh part). The RE7 name guesses were mostly wrong for Village (no `set_loadNum`, no string ids), so `player.cpp`
  now uses these: rounds set through the record, a new magazine = its own rounds back + the gun's `reload()` topping up
  from the carried ammo, a shell = `reload(1)`, and the magazine hidden with `switchMagazineDisp(false)` while it is out.
  The magazine joint animation (`_04`) is switched off (`MAG_JOINT_ANIMATE`) until a joint log shows the real part.
  What `reload()` / `reload(1)` exactly do is `[hypothesis]` until a headset run: every call logs the rounds before and after.
- **A caught crash at start-up, now gone:** the bridge's first hand-over ran at frame 1, before the plugin had hooked
  its mailbox, so the game's real setter ran with our array (`VMContext: Caught exception code c0000005`, caught by
  REFramework; it was in the earlier runs too). The first hand-over now waits ~3 s (frame 181); the next start attached on
  that first try with no exception `[verified-live 2026-10-18, n=1]`. Same fix put into the parked RE7 bridge.

Plugin `816bdefb`, installed 22:41. Still never run in the headset.

## 23:06 first headset run (Tefa): "B doesn't eject the magazine and LG in the ammo spot didn't pick up a shell"

The log `[verified-live 2026-10-18, n=1]`: right B DID take the magazine out (LEMI with 0 rounds, F2 with 6), but nothing
showed it; the ammo spot DID register the left grip, but every gun read "carried -1", so it refused. Causes and fixes
(plugin `41f8e1a0`, installed 23:20, unworn):
- "carried -1": `getBulletItemID` by bare name found the `(int)` overload and read 0. Now the exact `getBulletItemID()`,
  then the item record's `includeItemID`; the four answers of `getTotalStackSize`'s two unnamed bools are logged once per
  ammo kind; an unknown reading no longer refuses the grab (the game's own reload decides).
- nothing to see: `switchMagazineDisp(false)` alone hid nothing. The magazine is now the gun's mesh part
  `NormalMagazinePartsNo` (`...Customized` with a custom magazine), hidden after the animation while it is out.
- no joint list: `get_Joints` had no `get_Length`; now `get_Count` / `get_Item` (Andyalpa's RE7 scan), with the magazine
  part number on the same line.
- the game asks `tryReload` every frame (4,750 skips in a minute): logged every 2,000 now.

## 23:16 second and third headset runs: "the mag still doesn't come out with B"

The checks named it `[verified-live 2026-10-18, n=1]`: `gun transform NOT FOUND`, `gun object none`, `inventory NOT FOUND`.
In Village a gun is an item (`app.WeaponGunCore` -> ... -> `app.ItemCore` -> `app.Agent`), not a component, so it has no
`get_GameObject`: its object is its owner (`Agent.get_owner`). The player's inventory is not a component either:
`InventoryManager.get_activeInventory`. Both fixed in `player.cpp` (plugin `9025da76`, 23:25, unworn); the magazine part
hide, the joint list and the carried-ammo reading all depended on them. The bullet item ids did read (LEMI 1179972000,
M1897 1731811000).

Shells: the "0.20 m ahead along the barrel" point from the controller's turn came out 0.37-0.86 m from Tefa's hand, so long
guns now dock by the plain distance between the controllers (0.35 m; pistols 0.20 m). Racking also takes hold within
0.30 m of the right controller, long guns pull along the line from the right hand to the left, and every grab attempt
logs the gun line it used, to check the controller-turn reading.

## 23:20 run: the ammo works -- "the mag came out ... disappeared, ... no actual mag [in the hand], but when i put my hand close to the pistol handle the bullets loaded in"

`[verified-live 2026-10-18, n=1]`: B emptied the LEMI (9 rounds kept), the carried count read right (68; the bools change it
to 77 with the first one true: the second count includes something more, ff is used), the magazine went in at 0.199 m and
the game's own `reload()` topped it up (9 -> 10, carried 68 -> 67). The joint list finally printed, and **Village names its
gun joints**: LEMI `root, Body, Magazine, Bullet, Slide, Hammer, Trigger, vfx_muzzle, vfx_muzzle2, Cartridge,
Magazine_second`; F2 Rifle `root, Body, Magazine, Slide, Trigger, vfx_muzzle, Cartridge`. The magazine mesh part is 1 on
the LEMI (-1 = none on the F2). +Y is up and +Z forward in the gun's frame (the slide sits above, the muzzle ahead).
Next build (plugin built 23:35, installed when the game is closed): the magazine joint is `Magazine` (slides out, falls,
rides in the left hand on the hold), the part is hidden only once it is on the floor, the rack moves `Slide` (then `Pump`,
`Forend`, `Bolt`), the pistol dock is 0.24 m (two of three tries stopped at 0.43). No rack was tried: it only takes hold on
an empty / locked-open gun or with "Hold this pose" on (Tefa's RE2 rule).

Installed 23:26 (plugin `906e4e39`). Same moment, Tefa: "the flashlight activation zone needs to be up 10 cm and back 30 cm": Andyalpa's head-flashlight spot in his saved `re8_vr/re8_vr_holster.json` (profile default, headset axes, +Z = back) moved y 0.004 -> 0.104, z -0.069 -> 0.231 (backup beside it, `.before-flashlight-move-*`). A settings file of his, not our code.

## 23:30 run: "mag falls out, mag is visible in hand ... when trying to rack, hand jumps to the grip"

Magazine drop and the magazine in the hand work `[verified-live 2026-10-18, n=1]`. No rack was ever tried (no rack lines): the gun was never empty, so the slide was never due, and the hand went to the VR layer's grip dock as usual. Tefa: "suppress weapon docking on the handle when the slide needs racking and vice versa". Now (plugin `abc67b6d`, 23:32, unworn): with a rack due, the left grip HELD near the gun takes the slide (not only a fresh press), and the hand is placed on the `Slide` joint itself (measured against the gun hand after each frame, riding the slide back), keeping the turn the VR layer gave it; with no rack due it never goes on the slide. Menu "Visceral RE8 reload" has three sliders to nudge the hand on the slide (cm, gun axes), saved in `reframework/data/visceral_re8/slide_hand.json`.

## 23:40 Tefa: "the racking works! hand poses and activation ares need tweaking, but it works!"

Magazine drop, magazine in the hand, insert, and the slide rack with the hand on the slide all work in the headset `[verified-live 2026-10-18, Tefa, n=1]` (plugin `abc67b6d`). Next: Tefa's hand poses, then the activation areas (dock distances, the rack grab) tuned with Tefa. A 22 s clip of the run: `Visceral - Resident Evil Village VR - manual reloads, 18 October 2026.mp4` (and a 9.4 MB copy).

## 2026-10-19 00:06 run, other guns: "the gun most of the time jumps to the left hand and grips it, and then the mag gets inserted after that, without me having the rifle or the shell in my hand ... the ammo count didn't increase on hud"

Log `[verified-live 2026-10-19, n=1]`: the F2 bolt rack worked (dry reload -> rack NEEDED -> pulled 0.084 m -> 4 rounds in); the M1897 took shells 0.6 s after each grab, still at the hip (a long gun held low is within the 0.35 m controller distance); the pump joint is named `Pump` (rests 0 0.023 -0.076). The VR layer's two-handed grip locked on as the carrying hand passed the gun and stayed while LG was held. The controller-turn "gun line" readings jumped around (0.14 0.99 -0.06, then -0.90 0.30 -0.32), so nothing new leans on it. Fixes (plugin `57404b0c`, 00:14, unworn): (1) our `re8_vr.lua` reports the left grip as not holding the gun while `__visceral_reload_busy` (also stands down the scope mod's rifle grip, which follows the same flag); (2) while carrying a magazine / round, the left IK target is put back on the left controller (its place relative to the controller remembered whenever the grip is not locked); (3) a magazine / round goes in only with the left controller at least 0.15 m in front of the headset and no lower than 0.55 m under it; (4) after each ammo change the gun's own `ReloadHandler` is fired so the HUD updates `[hypothesis]`.

## 00:19 run: "the shell still doesn't show up ... ammo counter changes ... distance ... toned down to 10cm ... pump handle pumping doesn't work, game still does that automatically ... the bolt itself does not move at all"

HUD fix confirmed (the counter moves when a round goes in) `[verified-live 2026-10-19, Tefa]`. The M1897 joints: `root, Body, Reload_Slider (0 -0.014 0.228, the fore-end), vfx_muzzle, Bullet (0 -0.015 -0.013), EmptyBullet, Carrier, Hammer, Trigger, Bolt (0 0.023 -0.076), Bayonet, Cartridge`; our pump search had taken `Bolt`, and the pump grab missed (0.25 / 0.20 m off the gun line). Plugin `609b9e6b` (00:26, unworn): pump guns look for `Reload_Slider` first, the rack takes hold within 0.20 m of the slide / pump joint itself (left controller in the world); a pump gun needs the pump after EVERY shot (its shells wait, the HUD reads 0 until pumped; the game's own pump motion still plays); the shell in the hand is the gun's own `Bullet` joint on the hand hold; long guns take a magazine / shell when it is within 0.10 m of its place (the magazine seat, the Bullet joint's rest); the slide / bolt joint is also written at BeginRendering pre; the mesh parts and which are drawn are logged once per gun (which one is the loose shell).

## 00:31 run: "the shell showed up, but ... both the rifle mag and the shell do not even go in the weapon at all"

Shell in the hand and the manual pump work `[verified-live 2026-10-19]` (pump on `Reload_Slider`, cycles logged). The 10 cm insert never fired: closest 0.349 m (F2 magazine), 0.600 m (shell) to the spot computed from the joint's local numbers through the gun object, which was evidently wrong. Plugin built 00:40: the spot is now MEASURED: the magazine joint's world position at the drop, the Bullet joint's at the grab, kept relative to the right hand target. Still 0.10 m. The F2's mesh has 256 parts, the M1897's too (drawn masks logged).

## 00:39 run: "still doesn't go in"

With the measured spot the closest came to 0.138 m (F2 magazine) and 0.107 m (shell), so the spot is right and 0.10 m was just tight. Plugin `235cceda` (00:45): 0.16 m, and a log line when the item is close enough but the "in front of you at gun height" check stops it.

## 00:49 run: "still no to both, and shotgun shows 5 shells in the gun, but when i fire the ammo counter drops to zero"

Closest this time 0.349 / 0.418 m (vs 0.138 / 0.107 the run before): the check ran at LateUpdateBehavior, before the arm is solved, so it measured from the hand where the animation had it. Now at PrepareRendering post, after the IK. The zero counter was our own hold-back of the shells until the pump; now the rounds stay in the gun and `PlayerGun.tryAttack` (and `PlayerGunPl2001`) is refused until the rack / pump is done (plugin `571a6bdb`, 00:55, unworn).

## 00:57 run: "yep all work now, but the bolt action needs manually pushing back up, not let go and it snaps back like the pistol slider"

Magazine and shell inserts, the trigger block and the pump all work `[verified-live 2026-10-19, Tefa]`. Plugin `4c63cbaf` (01:02, unworn): the F2 rifles are bolt actions (`weapons.cpp` bolt): the bolt follows the hand both ways once pulled, finishes only when pushed home (travel <= 10%), and if let go before that it stays open where it is and can be taken again from there.

## 01:05 Tefa, how the F2 bolt must work, after every round: "turn the bolt up, pull backwards, then a gun click sound must play to signify that i can now push the bolt back forward and then back down to lock it in"

Plugin `0294722e` (01:10, unworn): a bolt cycle is due after every shot (trigger refused until then) and after a dry reload. Taking the bolt with LG is enough (no LT). Steps: the left hand lifted 5 cm against the right turns it up (the Slide joint turns 60 degrees about the barrel, sign a guess); pulled back to the end = Andyalpa's chamber-open click (RE7 VR Reloaded, `sfx/bolt_click.wav`, played with PlaySound) + buzz; pushed home; the hand lowered 5 cm turns it down = locked, done. Let go mid-cycle, it stays at that step. Turns are read from hand height, not controller rotation (those readings jumped).

Tefa, the same minute: "please make LT part of it still, so only LG on it's own does not start it, just like with the shotgun. LT needs to be pressed once". The bolt now starts on LG held + one LT press near it; LG alone keeps it going.

Then: "so the left grip must already grip it and hold on, but not move the bolt until LT is pressed". Now LG near the bolt puts the hand on it and holds; nothing moves until one LT press arms it (baselines taken at that press).

And: "same with every weapon". Plugin `b78edd21` (01:20, unworn): slide, pump and bolt all take hold on LG near their joint and hold the hand there; one LT press arms the movement; LT need not be held. The pump no longer springs back on LT release: it is pushed back up by hand (let go mid-way, it stays back). The pistol slide still flies forward when LG is let go after a full pull.

## 01:10 run: "rifle showed 0/0 ... should have been 1/4 until i fired the shot ... the bolt went the wrong way into the gun ... the bolt just wouldn't move as my left controller did ... on the shotgun, when just holding grip, my hand still moves around on the front part"

Log: after the dry reload the game had 4 in the F2 and 0 carried; the HUD only caught up on the next trigger pull. The bolt reached "turned up" and "back (click)" but never "home": its pull axis was the line between the hands, short and crooked with the left hand over the receiver. BeG0nE has no Village reports (the Village plugin has no Ghost Hand wiring yet; the 4 new reports are RE2). Plugin `f53a4715` (01:30, unworn): the bolt turns the other way (-60); the bolt and the pistol slide pull along the gun object's +Z carried into the room (the pump keeps the hand line, which works); the hand's spot on the slide / pump is frozen at the first measure after taking hold; after each ammo change the bridge Lua runs the game's remaining-ammo driver (`app.GUIRemainAmmo` via GUIManager.findGUI(1927694450): applyToUI + order.showRemainAmmo). Its calls are now in type_probe.txt (`updateInfo(int,int,int)`, `updateRemainAmmo`) if that is not enough.
