# Visceral RE8 (Village) — engine dossier

Started 2026-11-02 (the durable facts; the dated story is in `modding-notes/`). RE Engine, praydog's REFramework VR.

## §1 The REFramework build in use

- `dinput8.dll` 76298bd (praydog's pd-upscaler / DLSS loader build, 2026-03-11 package `RE8_pd-upscaler_76298bd_2026-03-11_original-package.zip`).
  **No .NET support**: praydog's RE Engine MCP (REFramework.NET.dll) logs "exception in reframework_plugin_required_version" and
  never starts `[verified-live 2026-11-02, n=1]`. A .NET nightly would bring it back, but swaps the VR base under the mod.
- Our own read-only lookup instead: `src/lookup.cpp` (questions `reframework/data/visceral_re8/lookup_ask.txt`, answers
  `lookup_answer.txt`; part of a type name / `member:` / `type:` / `tree:`, see lookup.h) `[verified-live 2026-11-02]`.

## §2 Shooting

- `app.WeaponGunCore` (player::now().gun) holds the next shot behind locks: `readyShootBySequence` (the shot animation done),
  `readyShootByTimer` (counts `ShootableTime`; **1.500 s on the M1851 Wolfsbane**), `readyShootByTriggerBack` (the trigger let
  go). Writing `readyShootByTimer = true` from UpdateBehavior pre does NOT hold: the game's timer update shuts it again before
  the shot is tried `[measured 2026-11-02, n=3]`. Also there: `ShootableTimer` (app.SimpleDecTimer), `resetShootableTimer()`,
  `updateShootableTimer()`, `setReadyShootBySequence(bool)`.
- `app.PlayerGun.requestShootForProcess(bool ignoreExpandBullet)` fires a round at once (ammo, sound), WITHOUT the muzzle flash;
  `requestShootForProcessEffectOnly()` called after it did not bring the flash back on every shot `[reported 2026-11-02, Tefa]`.
  `requestShootNoneBullet()` = a blank shot with the full gunshot sound (2026-11-01).
- `app.WeaponCore.isKeepHammerMotion` / `clearKeepHammerMotionFlg()` and `app.WeaponSpecialSetting.KeepHammer` exist: untried
  candidates for "the game never cocks the hammer" `[inferred-static 2026-11-02]`.

## §3 The ammo counter

- `app.GUIRemainAmmoOrder.updateRemainAmmo(System.Boolean isEnable)` (the order of the `app.GUIRemainAmmo` driver) refreshes the
  count: called with `true` after each round in, the counter follows `[verified-live 2026-11-02, Tefa: "the bullets are counting right!"]`.
  (Calling it with (mode, item) did nothing, 2026-10-31.) The driver's own `updateRemainAmmo(app.GUIRequest.Parameter)` untried.

## §4 The M1851 Wolfsbane's model

- Joints: root, Body, Trigger, Hammer, Cylinder, Five_/Seven_Bullet00.., Lid (the loading cover), vfx_muzzle. It loads through
  the cover (no swing-out crane) (Tefa, 2026-11-01).

## §5 Leads handed over by the other lanes (drained from inbox/ 2026-11-02)

- **Accuracy from movement:** no spread value is needed; the scope project replaces the shot's rotation at the bullet
  build step (hip shots flew straight on the sniper rifle `[verified-live 2026-09-21, n=10]`, scope project dossier
  §9bk/§9bl). Blend clean and scattered rotations there, weight from movement and the two-hand grip; check a pistol and
  the shotgun use the same step first. Topic: `external-research/topics/2026-10-26-accuracy-from-movement-*.md` (/gr).
- **Drawn spheres ignore their size:** public RE Engine mods parent the mesh to the gun and size it each frame with
  `set_LocalScale`, not `set_Scale` `[reported 2026-10-26]`. First step: read back get_Scale / get_LocalScale (/gr).
- **ri5052 is a knife:** Andyalpa's holster profile saves `"last_knife_id": "ri5052"` `[inferred-static 2026-10-26]`;
  ri5003 probably another knife `[hypothesis]`. The stalled swap that crashed was likely the knife's INVENTORY item (/gr).
- **The standing origin** is taken from the head at VR start and again on every OpenXR recenter, never saved
  `[inferred-static 2026-10-26, REFramework source]`; Lua `vrmod:get/set_standing_origin`. A height pin is a stop-gap (/gr).
- **Ghost Hand over 107 runs** `[measured 2026-10-19..25]`: gestures finish slide 40/40, breech 24/24, pump 153/155,
  shell 121/124, mag 212/228, bolt 98/127. The bolt logs no `_need` so its misses cannot be judged; 16 runs logged the game
  hand ~156 m away (world vs room space, before the camera was found): ignore those runs' jump and lag numbers (/gd).
- **Log facts 2026-10-27..11-01** `[measured]`: the (mode, item) ammo call was rejected (superseded: §3, the bool call
  works); `hand_poser/command.json`, `zones_open.json`, `zones.json` read empty thousands of times (harmless, buries the
  log: check size before `json.load_file`); `[visceral-re8-hud]` cannot find `app.GUIRequestOpenQuickEquipParameter` or
  `app.PlayerUpdater`; the `set_FontSize` access violations stopped after 10-31 (/gd).
- /gs 2026-10-27: the board's OPEN block had not been re-dated after an entry (re-audited since).

- 2026-11-05, Gold Digger (dev PC) from the collector's shelves: **the Emporium's `via.gui.Text.set_Message` calls fail in storms of up to 1000 a minute while a shop screen is open, and those minutes are the worst stutter the perf recorder saw** (38 fps, 240 stutters a minute; processor and graphics clocks halve while the main thread sits in exception handling) `[measured 2026-11-05]`. A second stutter stretch at 21:06 on 11-04 had no storm (a script reload / Sell: `[hypothesis]`). Board row on `status/visceral-re8-vr.md`. Drained from `inbox/2026-11-05-gd-emporium-text-crash-storms-are-the-stutter.md`.

## §6 The GUI system and the Duke's shop (2026-11-04, flat, Lua probe)

- A screen is made by `app.GUIManager.createGUI(UInt32 alias, Boolean)`; **the alias is the RE Engine name hash**
  (murmur3_32 UTF-16LE, seed 0xFFFFFFFF) of the screen's short name: `createGUIShopBuy()`'s handle has alias
  3474722425 = hash("ShopBuy") `[verified-live 2026-11-04, n=1]`. The handle (`app.GUIHandle`) holds the screen's
  driver component (app.GUIShopBuy and kin, all `app.GUIDriver`s: show / hide / execute(GUIRequest) / set_drawSuspend /
  onShow / get_GameObject), `isManaged`, `aliasHash`, `isForceHide`.
- Shop screens by name: Shop (top; menuHandle, bgHandle, initialMode), ShopBg (the wall: a `via.render.Mesh` with its own
  camera numbers, so a 3D object in front of the camera, VR-visible), ShopBuy (1302 controls), ShopSell, ShopCustomize,
  ShopRecipe, and **ShopMenu** (app.GUIShopMenu: the three cards, found by a 340-name scan `[verified-live 2026-11-04]`; its
  `l_list` holds si_list0..2 with texts m_name0 (title) / m_name1 (motto), the `header` m_header / m_header_desc). `app.GUIShopMode`:
  Menu / Buy / Customize / Sell / Recipe (hashes of those words). `via.gui.Text.set_Message(string)` takes our words (16 of 16 on
  ShopBuy). ⭐ `app.GUIDriver.show(app.GUIRequest.Parameter)` with a fresh empty Parameter SHOWS a 2D screen (ShopMenu: the three cards, over
  the village, taking the controls; the call throws after doing its work) `[verified-live 2026-11-04, n=1]`; drawSuspend off alone
  draws nothing; onShow(true) throws on ShopMenu and crashed on ShopBuy. A driver's order words (ExecuteDict keys = name hashes):
  Suicide, Show, Hide, SetSegment, SetState, SetAttachTarget, EnterExclusive, LeaveExclusive, + one unknown (4213754707). `suicideGUIShop()` takes a shown ShopMenu off cleanly; `sdk.create_instance("app.GUIRequest")` is nil from Lua.
- ShopBg shows in gameplay with `set_drawSuspend(false)` + `onShow(true)` on its driver `[verified-live 2026-11-04,
  n=1]`. ⛔ The same on a ShopBuy with no data crashes the game `[verified-live 2026-11-04, n=1]`.
- GUI game objects are named "GUI" + alias (GUIShopBuy, GUIShopBg, GUIMouseCursor); `re.on_pre_gui_draw_element`
  sees 2D GUI draws (the cursor) but not the mesh-based wall.
- Story: `modding-notes/2026-11-04-the-dukes-shop-by-name.md`; probe: `dev-archive/native/lua/visceral_re8_shop_probe.lua`
  (installed in the game's autorun, driven by `reframework/data/visceral_re8/shop_probe.json`).

## §7 Finger joints: the engine's Euler angles (2026-11-05, flat, probe)

`via.Joint.get_LocalEulerAngle` / `set_LocalEulerAngle` use the order **YXZ**: the quaternion is qY(y) * qX(x) * qZ(z), the Z
turn applied first `[measured 2026-11-05, 12000 samples on 30 finger joints, 0.0000 deg error]`. Hand Poser writes these
angles; `dev-archive/native/tools/make_rest_poses.py` turns the takes' quaternions into them. Probe: `lua/archive/zz_euler_probe.lua`.

## Dead ends

- praydog's connector on the 76298bd build (§1). The game's held-trigger shot with only `readyShootByTimer` forced (§2).
