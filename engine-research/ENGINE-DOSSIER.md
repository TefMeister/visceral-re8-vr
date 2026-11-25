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

## §8 How a magazine shows its rounds (2026-11-05, simulator, LEMI)

`app.WeaponGunCore.switchVanishEmptyPartsDisp` lists the gun-mesh parts that vanish when the magazine is empty (the LEMI: part
50, the rounds; `IsEnableVanishEmptyPartsDisp` on); `execSwitchVanishEmptyPartsDisp()` switches them from the gun's own round
count (on at 2 and 1 loaded, off at 0) `[measured 2026-11-05]`. `NormalMagazinePartsNo` is the magazine itself (LEMI 1);
`SecondMagazinePartsNo` (LEMI 11, flag "vanishes when empty") stayed ON at 0 loaded, so that flag is not this switch
`[measured 2026-11-05, n=1 gun]`. The magazine held in the left hand is the gun's own mesh, so these parts rule its look too;
`src/magdisp.cpp` overrides them while it is out. Type list: `type_probe.txt`.

## Dead ends

- praydog's connector on the 76298bd build (§1). The game's held-trigger shot with only `readyShootByTimer` forced (§2).

## Inbox drained 2026-11-15 (/pd)

- **Ghost Hand distances since about 2026-11-01 are in two spaces** (the game hand ~156 m from the controller in every
  report): those reports' distances are unusable; their rack / magazine / shell event lines still read right
  `[measured 2026-11-05, /gd]`. Cause not found `[hypothesis: room space against world space]`.
- **"Empty" settings files are MISSING files** (`visceral_re8/magthrow.json`, `re8_vr_haptics.json`,
  `village_character_joints.json`, Hand Poser's `guns/`): REFramework reports a missing file as a parse error at line 1;
  the built-in defaults are used, as designed `[measured 2026-11-07, /gd]` (supersedes the 11-05 "empty" reading).
- **The .NET connector dead end** (§1, "no .NET support"): the same log line on an ordinary nightly was cured by the .NET
  10 Desktop Runtime `[reported, REFramework #1739]`; the throw is the managed DLL failing to start .NET
  `[inferred-static 2026-11-11, /gr]`. Read §1's dead end as "REFramework.NET failed to start .NET, cause not separated"
  until `dotnet --list-runtimes` shows `Microsoft.WindowsDesktop.App 10.x`.
- ⚠️ **`re8_vr_holster.lua` is at Lua's 200-locals limit** (~204 by the /gs estimate, the same since b069): one more
  top-level `local` there and the script stops loading with no warning until the game runs it. Any new holster code
  goes elsewhere (or into a table) `[measured 2026-11-11, estimate]`.
- The OPEN heading's form was fixed on the board before this drain.

## Menu button: tap = map, held = pause (2026-11-15, /lm reader + simulator)


From: the static reader of the 2026-11-15 live session (files only; the game was running under another driver and was
not touched). For: the board row "TEFA'S SHARED BASE LAYOUT FOR EVERY VISCERAL GAME", item (a).

### 1. How the menu button becomes pause in Village today

- Village runs praydog's STOCK REFramework: the game's `dinput8.dll` has the same sha256 (8730941f...0594) as the one inside
  `RE8_pd-upscaler_76298bd_2026-03-11_original-package.zip`; `reframework_revision.txt` = 76298bd9 `[measured 2026-11-15]`.
  The source tree at that commit is `D:\ref-76b` (`git show HEAD:src/mods/VR.cpp`; the working copy there carries RE2 edits).
  So there is no Village REFramework patch today, and a C++ route would mean Village's first custom REFramework build.
- Runtime: OpenXR (no `openvr_api.dll`; today's log: "Initializing OpenXR", system name "OpenXR Simulator") `[measured 2026-11-15]`.
- The bindings file in the game folder (= `dev-archive/native/bindings/`, identical) binds `systembutton` to
  `/user/hand/left/input/menu/click` only. The right controller's menu button is the Oculus button, not given to apps.
  The file replaces REFramework's built-in Touch bindings (`OpenXR::initialize_actions` clears `profile_bindings` before
  reading it) `[inferred-static]`.
- The chain, per frame `[inferred-static, 76298bd OpenXR.cpp / VR.cpp; order measured 2026-09-27 by the scope mod]`:
  1. `HIDPadManager.doUpdate` runs first. `re8_vr.lua`'s pre-hook (`update_padman` -> `update_pad_device`) writes every pad
     bit onto the ACTIVE pad's device (`set_Button` / `set_ButtonDown`).
  2. UpdateHID entry, pre: `VR::on_pre_update_hid` -> `update_action_states` -> `OpenXR::update_input`:
     `is_action_active_once("systembutton")` (the PRESS edge only) sets `runtime->handle_pause = true`.
  3. The scope mod's `reframework/autorun/re8_vrz_scope_sounds_menu.lua` ("the left menu button fix", re-village-scope-vr,
     loaded today: log 18:28:43 "menu: left menu button fix installed") watches `should_handle_pause()` on both sides of
     UpdateHID, clears it, and presses `via.hid.GamePadButton.CRight` (32768) on the active pad now and on the next 2
     doUpdates `[verified-live 2026-09-27, n=1 session: "seen before UpdateHID", pause pressed; scope board]`.
  4. UpdateHID post: `VR::on_update_hid` (`#ifdef RE8`) would `set_Button(CRight)` on the MERGED pad's device if the flag
     were still set; it normally is not (step 3 cleared it). praydog's own route alone lands on a pad nobody reads once the
     game switches its active pad (the scope mod's 2026-09-27 finding).
- `re8_vr.lua` itself never sees the menu button: the Lua API has no getter for the system-button action
  (`get_action_*` exists for trigger, grip, joystick, joystick_click, a, b, weapon_dial, minimap, block, dpad_*, heal), and
  its only `should_handle_pause()` use is `is_re7` `[inferred-static]`.
- So today a PRESS pauses at once; hold or tap make no difference.

### 2. Which pad bits open the map, the files, the pause

- **Map = `CLeft` (16384)** `[inferred-static]`: praydog's `re8_vr.lua` turns the "minimap" action into `CLeft` (RE7 and
  RE8 alike). Today it fires from the right-hand minimap check, which is true through praydog's fallback in
  `VR::is_action_active`: left Y + the left hand behind the head (`is_hand_behind_head`, < 0.3 m). That is the "map at the
  back" gesture. Not seen live from the files.
- **Pause = `CRight` (32768)** `[verified-live 2026-09-27 through the scope mod; inferred-static for praydog's path]`.
- **Inventory = `RUp`** (Xbox Y) `[measured earlier, re8_vr_holster.lua comment "Runtime scan confirmed RUp"]`.
- **Files**: no pad bit found. praydog's `re8_map_names` = `GUIMap`, `GUIBinder` (the "binder" is most likely the files);
  both are "UI that needs the D-pad up/down" `[hypothesis: the files are a tab of the map screen]`. No type or input dump
  exists on this PC for Village (the `reframework/data` folder has none), so this needs one flat look: send `CLeft` once,
  see which screen opens and how to get to the files from there.

### 3. The draft (a Lua route exists, so no C++)

Files in `staging/visceral-re8-vr/menu-button/` (not committed, nothing installed):
- `bindings-menu-button.patch` + the changed `_interaction_profiles_oculus_touch_controller.json`: the left
  `menu/click` is bound to `heal` instead of `systembutton`. `heal` exists in the 76298bd action list (boolean), nothing
  binds it on Touch, Lua can read it (`get_action_heal`). With `systembutton` gone, `handle_pause` is never raised by the
  button, so the scope mod's fix and VR.cpp both stay quiet. REFramework reads the file only at start: a game restart is
  needed for it to take effect.
- `re8_vr-menu-button.patch` + the changed `re8_vr.lua` (against the repo copy, sha256 d23fdcaf...ba60; CRLF kept;
  `luac -p` passes; main-chunk local count unchanged, all state in fields of the existing `vz_pad` table):
  - in `update_pad_device`, after the `is_re7` pause line: left `heal` read each pad update; press time noted; held 0.3 s
    -> `CRight` for 2 pad updates (the scope fix's proven count), once per hold; released before 0.3 s -> `CLeft` for 6
    pad updates (RE2 / RE3's map pulse). One log line each: `[visceral-re8] menu button: tap (... s) -> map / files (CLeft)`
    or `... held 0.3 s -> pause (CRight)`.
  - the heal line no longer reads the LEFT heal action (it would press `RTrigTop` = heal on every menu press); the right one
    stays (unbound on Touch). `re8_vr_holster.lua` only copies `heal_l` into a state snapshot (line ~8073), no behaviour.
  - Either half alone is safe: Lua without the new bindings = menu_now always false, the old instant pause stays; the
    bindings without the Lua = the menu button does nothing.
- The button is read in doUpdate, which runs before UpdateHID syncs the controllers: one frame late, harmless.
- A C++ route (a `visceral_menu_*` block in `VR::on_update_hid`'s RE8 section) is possible but would need a custom
  REFramework for Village; not drafted.

### 4. To check live (the first wear)

1. One flat look: `CLeft` opens the map screen, and where the files are from there `[hypothesis until then]`.
2. Virtual Desktop: the scope note of 2026-09-27 says VD "only claims a double press or a hold" of the left menu button
   `[reported 2026-09-27]`. If VD's hold is short, the 0.3 s hold may never reach the game. Watch for the "held 0.3 s" log
   line in the headset (the OpenXR Simulator running today may not have a menu button at all).
3. A tap while the pause menu is open sends `CLeft` there; a second 0.3 s hold should close the pause (`CRight` again).

### 5. Worth knowing for RE2 / RE3 (outside this job)

- The named file `visceral-re2-vr/dev-archive/reframework-patch/2026-11-15-re2-re3-shared-layout-menu-and-dodge.patch` does
  not exist yet; the `visceral_menu_*` block sits only in `D:\ref-76b\src\mods\VR.cpp` (working copy, 16:48), and
  `D:\ref-76b-re3` has none.
- That block keeps `|| get_runtime()->handle_pause` on the PAUSE line. RE2 runs OpenXR (its log 2026-11-12: "Initializing
  OpenXR", no openvr_api.dll) and its bindings file still binds `systembutton`, so every menu PRESS raises `handle_pause`
  and pauses at once: a tap would pause AND then open the map `[inferred-static]`. The fix there: drop the `handle_pause` term
  (keep only `visceral_menu_held`), or clear `handle_pause` without using it.

- **Live, the same session (simulator + VR Bench, b134):** tap = the map, tap again = closed, 0.6 s hold = the pause menu, staying open, once the scope mod's fix stood aside (`__visceral_menu_owner`); before that switch a hold paused twice (open + close) because the press still raised the pause signal on the simulator `[verified-live 2026-11-15, simulator, n=1 each]`.

## §9 Meshes we make at run time (2026-11-25, /lm, flat)

- `via.render.Mesh.setMesh` takes `via.render.MeshResourceHolder` and `set_Material` takes
  `via.render.MeshMaterialResourceHolder`: `sdk.create_resource(kind, path):add_ref():create_holder(kind .. "Holder")`.
  A bare resource is refused (b171's "the object took no mesh") `[verified-live 2026-11-25, n=2]`.
- A material file's first load takes some seconds; until it is in, the mesh shows the engine's dark checker pattern.
  Load every material a script may swap to once the player is in play `[verified-live 2026-11-25, n=1]`.
- On the title screen the guns' textures, and even the GM 79's own mesh from the pak, never became ready
  `[verified-live 2026-11-25, n=1]`.
- Item ids are the murmur3 name hash (UTF-16LE, seed 0xFFFFFFFF) of short names: ammo `ri20xx` (ri2042 = 1927571624, the
  GM 79's explosive round), the GM 79 `ri3023` = 2576167331. A gun's rounds are listed in its inventory item's
  `<spec>k__BackingField.Weapon.IncludableItems`: the GM 79 takes 1927571624 (explosive) and 1583016682 (flash)
  `[measured 2026-11-25]`.
- The GM 79's round is four joints under `Carrier`: Ammo01 the case, Ammo02 / Ammo03 the fronts 4.5 cm ahead, Ammo04
  `[measured 2026-11-25]`. Its ammo kinds: the slot (`set_requestedUsingBulletIndex` + `applyRequestedBulletIndex`) sets only
  the next reload's kind; `reload(n)` loads the MAIN record's `IncludeItemID` at either slot (Sub never filled); a round given
  back by `addItem` goes to a hidden stack the carried count ignores `[verified-live 2026-11-25, n=1 each]`.
- In Duke's area the game keeps guns away: a gun equipped there comes out the moment the player steps out `[seen 2026-11-25]`.

- **A via.Joint written at BeginRendering stops the engine drawing other things anew** `[measured 2026-11-25, flat, n=2 + 2
  controls]`: on Tefa's lift save Duke stood frozen while his animation ran (moving platforms and guns wrong too) whenever our
  plugin wrote any joint there; PrepareRendering writes alone are fine. b177 writes none at BeginRendering. Found by one launch
  per guess with `off.txt` (plugin parts and phases off without a rebuild) and `tools/sim/liftrun.sh` + `regiondiff.py`.
- **Hooking via.Joint's setters freezes the same way** `[measured 2026-11-25, lifttest, FAIL 315/115 with the hooks, PASS
  3143/3453 without]`: a REFramework hook on set_LocalRotation / set_Rotation / set_LocalPosition / set_Position / set_LocalScale
  alone froze Duke. Do not hook them. (A plain file scan run by the plugin at the first frame also failed 2 of 2, off passed 2 of 2:
  mechanism unknown, possibly chance; the guard scan runs at install time instead, tools/check_begin_joints.py.)
- The lift test: `tools/sim/lifttest.sh` (or `build.sh --deploy --lift`), PASS / FAIL / SKIPPED, on Tefa's lift save (slot 11).
- A mesh must name the same materials, in the same order, as its mdf2, or the engine takes none (the checker pattern)
  `[verified-live 2026-11-25, flat, n=1]`.

## Inbox drained 2026-11-25 (/lm)

- Gold Digger 2026-11-21: a second crash spot, `re8.exe+0x49F5794` reading address 0x220 (a null pointer), run of
  2026-11-14 22:46, not written up before; `[hypothesis]` a game object already gone during a load, the same family as
  the holster-marker crash at `+0x415879c`. Ghost Hand's hand-lag reports of 2026-11-14 / 11-17 (7-12 frames behind) may
  mix world and room spaces, as the 11-16 report warns: numbers not trusted.
- Gold Digger 2026-11-25: only b164 froze that night (02:34 and 02:43 runs); the other "Present no longer called" runs were
  normal quits. A caught access violation in `via.Joint.set_Rotation` on the first VR frame (2026-11-23 10:24) right after
  the zones script's gun-turn line `[hypothesis]`: a joint written before the body is ready; low.
- /gr 2026-11-25, weakened by /gs the same day (its Supersedes line): REFramework's kananlib heap-lock start-up deadlock
  (fixed upstream 2026-11-17, our `pd-upscaler` 76298bd lacks it) stays a known hazard, but the two b164 freezes do not
  show its sign (Suspending 81 = Resuming 81). The b163 / b164 changes and the newer `hand_poser.lua` stay the first
  suspects. Flat runs of b171 and b172 on 2026-11-25 (both carry b163 / b164) played without freezing `[measured, n=2,
  flat only]`.

- /pd 2026-11-25 (Fable), the crash at `re8.exe+0x4151C23` read from two dumps (note
  `modding-notes/2026-11-25c-the-crash-at-4151c23-read-from-the-dumps.md`): +0x4151C00 is the engine's `release` of a
  managed object (header at +0, hold count at +8; a negative count = a thread-local object, its place in the creating
  thread's table of locals); +0x41510E0 is `add_ref`, which takes a local out of the CURRENT thread's table
  `[inferred-static]`. Both crashes: `app.ThreadPoolMergeExecutor.lateUpdate` -> `ThreadPoolList<T>.merge`
  (+0x20AC2A0, shared by every object list; REFramework labels it `<app.GUIRequest>`) -> `List.Clear` ->
  `Array.Clear` -> `release` on an entry whose header was already gone; sub-list 0, one entry `[measured, n=2]`.
  Not a GameObject path. Suspect `[hypothesis]`: the bridge's 2-s ammo counter refresh (`GUIRemainAmmoOrder` calls
  from the UpdateHID callback, since 2026-11-11), the only script code that makes the game queue requests in play.
  REFramework's crash log names unknown native code `via.dti.finalize`: a nearest-name guess, not a finalize call.
  +0x415879C (the 2026-11-14 crash) is a virtual call on an object with a bad header: a different path.
  Tools: `dev-archive/native/tools/crash/`. Rule set that follows: `modding-notes/2026-11-25d-clean-rebuild-2-design.md` section 5.

- /lm 2026-11-25 (Fable), from zero: the Village folder is the stock game (Steam's file check) + praydog's REFramework
  nightly 01451 (22c713ce, ONE dinput8.dll for every RE Engine game) + his `re8_vr.lua`, `utility/`, `vr/` +
  `openxr_loader.dll`. One flat start: loads, 89 / 89 threads resumed, reaches the game's Initial Settings
  `[verified-live 2026-11-25, n=1, flat]`. Its menu has a `ManualFlashlight` module the March build lacked. ⚠️ Every
  finding above this line was read on the March build (pd-upscaler 76298bd) with the old mod installed; b178 and that
  folder are kept in `D:/RE Village REFramework builds/full-backup-2026-11-25-b178-before-rebuild-2/`. Note:
  `modding-notes/2026-11-25e-from-zero-the-wipe-and-the-new-base.md`.
