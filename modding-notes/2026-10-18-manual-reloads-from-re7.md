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
