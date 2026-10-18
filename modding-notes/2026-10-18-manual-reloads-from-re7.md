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
