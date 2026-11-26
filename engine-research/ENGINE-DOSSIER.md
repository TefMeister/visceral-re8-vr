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

## §10 The prologue with Rose, and how praydog's layer hides and hands over the body (2026-11-26, /ms, headset, nightly 01451)

Detail and Tefa's words: `modding-notes/2026-11-26-from-zero-step-1-rose-the-scene-list.md`.

- The player object is `pl9000` at the title and in the book scene's lead-in, `pl1000` in play `[measured, n=3]`.
- Ethan carrying Rose has no game event and raises none of `re8vr`'s flags. Its marker: the object `pl5000` is a
  first-level child of the player's transform, from the first frame of control until the crib event `c10e050_00`
  starts `[measured 2026-11-26, n=3 runs]`. The event before control is `c10e001_00`.
- The carry's motions (layer 0, bank 0): id 0 `ch01_0000_Baby_001_Idle_Loop`, 4 / 5 `Baby_410_Turn_L75` /
  `Baby_411_Turn_R75`, 9002 `Baby_100_Dandle` (the patting on the stairs), 1 = ONE blend of
  `Hands_Walk_HoldBaby_Loop`, `Hands_WalkB_..`, `Hands_WalkL_..`, `Hands_WalkR_..` `[measured, n=1]`.
  `via.motion.MotionNodeCtrl` offers only `get_Weight`; `via.motion.TreeLayer` has `getMotionNodeCount`,
  `getMotionNode`, `getNodeParameter`, `trySetNodeParameter` `[measured: method names]`.
- Hand travel against the eye camera while carrying: 6 cm forward and sideways, 2-3 cm backward, 0 standing; head and
  hip 0 `[measured, n=1, 90-frame windows]`.
- `re8vr:update_hand_ik()` skipped = the game's own arm motion shows (praydog does it for `c32e390_01..09`; we do it
  for the carry) `[verified-live 2026-11-26, n=1]`. Skipping `update_body_ik` too changed nothing Tefa could see in
  the bob `[reported, n=1]`.
- The body is hidden by `RE8VR::fix_player_shadow` at pre-LockScene: DrawDefault off on the upper and lower body
  meshes when the controllers are not in use, or when (`is_in_cutscene` or not `can_use_hands` or grapple aim or a
  vehicle) and the "Auto Hide ... in Cutscenes" settings are on (`RE8VR_AutoHideUpperBodyCutscenes`,
  `RE8VR_AutoHideLowerBodyCutscenes` in `re2_fw_config.txt`) `[inferred-static from RE8VR.cpp at 22c713ce + measured]`.
  Setting DrawDefault back on from `re.on_application_entry("LockScene")` wins for that frame `[verified-live, n=1]`.
- A running event's name: `re8vr.game_event_action_controller` -> `_GameEventAction` -> `_EventName`; it stays up
  for the whole scene (c10e050_00: 14 s) `[measured, n=3]`.
- `re8_vr.lua` on the nightly still asks `is_openxr_loaded()` before OpenXR is up (26 ms early): the OpenVR hand
  offsets stay unless asked again `[measured, n=1]`.
- `VR_DecoupledPitch=true`: a cutscene's camera no longer tilts the view `[verified-live, n=1, Tefa]`.
- `app.PlayerMeshController` fields include `FaceMesh`, `HairMesh`, `HeadShadowMesh`, `HeadJoint`; methods
  `updateHeadMesh`, `updateParts`, `updatePl1000Parts` `[measured: names only]`. `getComponent` for it on
  `re8vr.player` gave nothing from our script: unexplained (RE8-083).

## §11 The body in VR: who turns it, who places it, who slides it (2026-11-26, /ms, headset, nightly 01451)

Full account, with Tefa's words: `modding-notes/2026-11-26b-from-zero-step-2-the-frame-worn-the-body.md`.

- **Who turns the body:** `app.PlayerMovement.destinationAngle()` answers "which way should the body face", in
  degrees, and the loader has made the camera the head. A post-hook that returns our own yaw turns the body, legs
  and all, and touches nothing else `[verified-live 2026-11-26, headset, n=6+ runs; first proved 2026-11-10 on the
  simulator]`. On the bare base the body does not follow the head standing still and snaps to it when walking
  `[reported, Tefa 2026-11-26]`.
- **The game walks along the BODY, not the camera** `[verified-live 2026-11-26, n=2: with the body held, stick
  forward went where the body faced until the stick was turned]`. The 2026-11-10 note's "walking still goes where
  the head looks" is wrong `[disproved]`. The stick is handed to the game in ONE place: `re8_vr.lua`,
  `device:call("set_AxisL", ...)`. Turned by a = head - body, `(x cos a - y sin a, y cos a + x sin a)`, stick forward
  walks where the head looks (a in the `atan(f.x, f.z)` yaw measure of the camera controller's rotation).
- **The lower spine turns toward the view:** `Spine_0` turns about the up axis by half of (head - body), `Spine_1`
  by the same amount back; `Spine_2`, the neck joints and the hip do not `[measured 2026-11-26, n=1 run, 45 lines,
  -15 to +19 degrees]`. Who does it (the game or the loader's body solver) is not known. Written back at
  post-PrepareRendering it reads constant `[measured, n=1 run]`.
- **Who places the body:** the loader, every frame: `RE8VR::update_body_ik` sets `via.motion.IkLeg`'s
  `CenterOffset` (`CenterPositionCtrl` 2 = world offset) to (camera position - the body's t-pose head joint), with
  a shift along the camera's flat direction of `0.025 - 0.1 * |look down|` m `[read from the source, 2026-11-26]`. It
  is also `re8vr:update_body_ik(rotation, position)` from Lua, and a second call in the same frame stands
  `[verified-live 2026-11-26, n=5 runs]`. The centre offset moves the hips and all above; the feet stay planted.
  The camera transform's `rotation * (0, 0, 1)` points BEHIND the view `[verified-live, n=1: the body went back]`.
- **Who slides the player:** `re8_vr.lua`'s `UnlockScene` block: when the headset is off the standing origin it
  lerps the origin toward the headset and sets the player's position by the same length every frame
  (`cfg.roomscale_movement`) `[read]`. No walk motion plays: the feet drag `[reported, Tefa]`. Left out, with the
  stick pushed toward the headset instead and the origin moved by as far as the player really went, the game
  walks him with its own step motions `[verified-live 2026-11-26, n=4 runs]`. A stick push of 0.18 still walks
  (0.5 reads as a dash) `[reported, Tefa]`.
- **The eyes are not the neck:** the headset's position is the eyes, about 9 cm in front of the axis the head turns
  on. Anything placed under "the head" (the hips, the test for a step) must use the neck (eyes + 9 cm behind the
  head's flat direction), or a head that only turns drags it `[verified-live 2026-11-26, n=3 runs: hips, then
  steps]`.
- **Rose** (`pl5000`) hangs on Ethan's `L_Wep` joint (`get_ParentJoint`) `[measured]`. The swing while walking is
  the walk motions' arm travel from the shoulder down: hip to shoulder 0 cm against the eye camera, upper arm 1,
  forearm 5 / 3, hand 6 `[measured 2026-11-26, n=1 run, 40 windows]`.
- **A sleeping controller** (Quest 3 through Virtual Desktop, OpenXR): keeps reporting its spot for about 6 s after
  it is put down, then reports the position 0 0 0 until picked up; `vrmod:is_using_controllers()` stays true
  `[measured 2026-11-26, n=1, both controllers]`. The hand at 0 0 0 is the hand at the face.
- **Joints written at post-PrepareRendering show** in both eyes (arms, fingers, spine) `[verified-live, headset]`,
  and an object that hangs on a written joint (Rose on `L_Wep`) goes with it `[measured: under 1 cm]`.
- Village's window takes the window's own close message cleanly with the headset in use too; the process leaves
  within a minute `[verified-live 2026-11-26, n=3]`.

## Dead ends
- 2026-11-26: a dead zone for the body's PLACE with a plain ease (8 cm, before the neck was in): Tefa: "here is
  where we can't really have a dead zone and need a lag instead". With the neck followed and a damped follow, a
  dead zone of 1 cm is what he kept (3, 6, 15 tried). The neck shift added AFTER the follow leans the body the
  other way at once. The body's back shift measured behind the HEAD swings the body against a turning head.
- 2026-11-26: for the body turn, a wide free zone (35 / 60 degrees) and no dead zone at all (always following,
  0.25 s) were both worn and both replaced; a dead zone then a full turn is what Tefa kept (25 degrees, 0.18 s).

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

## Doors: states, sounds, the type database off disk (2026-11-26, /pd, no game running)

- The exe carries the whole managed type database; `flat-to-vr-RE-toolkit/tools/tdb-read.py <re8.exe> type <name>` prints
  any class's fields and methods with no game running (version 69). Its door-state numbers equal the eight read in the
  running game on 2026-11-19 `[verified-numerically 2026-11-26, 8 of 8]`.
- Door states (`app.DoorStateNames`, name = murmur hash): Closed 474011919, Closing 3360157036, LittleOpened 171654102,
  **LittleOpening 2329368004**, Opened 3232296810, Opening 887278378, Push 396010129, Locked 3401490761, External
  2304963444, CurveAnimation 4118602539 `[inferred-static 2026-11-26]`. DEAD END: "LittleOpen = 3407536511" (b178) is
  no state `[disproved 2026-11-26, by the list]`.
- Door sounds: `app.DoorBehavior.CallSE(app.DoorSeTriggerType.Value)` / `CallSE(System.UInt32)`; ten kinds: Locked
  3401490761, CreakSlow 1884312664, CreakStop 3741696246, OpenKnob 3881480549, OpenLock 3567993302, OpenSlow 165766960,
  CloseCreakShort 2057132247, CloseCreakLong 2638778551, Close 1212689092, CloseSoft 3119021430 `[inferred-static
  2026-11-26]`. Which kind plays at which moment: not known `[hypothesis: OpenKnob = the first "partly open" sound]`.
  DEAD END: the hashes are code immediates only in the type's static constructor, so "which state calls which sound"
  cannot be read from immediates.
- Full write-up: `modding-notes/2026-11-26c-from-zero-step-3-doors-by-hand-on-the-frame.md`.

## Doors and the VR layer's cutscene flag, from the headset (2026-11-26 evening, /ms)

- Every door open fires the sound kinds OpenKnob and OpenSlow in one frame; CreakSlow / CreakStop only while the game
  itself moves a leaf; CloseCreakLong then Close (or CloseCreakShort then CloseSoft) on shutting `[measured 2026-11-26,
  the log of four runs]`. Each play is one `CallSE`.
- Several door objects can share one hinge and the game draws one (the bolted village door: `Before_Dynamic/..._Out`,
  `After1_Dynamic/...DoorOneWayLock_1Way`, `After2_Dynamic/..._Door_Dynamic`). An `app.InteractDoor` names its door in
  its `Door` field; `via.GameObject.get_Draw` told the shown one from the hidden two `[measured, n=1 door]`.
- `InteractDoor.StartInteractDoor(player)` opens an ordinary shut door `[verified-live 2026-11-26, Tefa, many doors]`;
  it does nothing on a door standing a crack open (LittleOpened) or on the one-way-lock door `[measured, n=1 door]`.
  DEAD END for those: letting the walk-in call through for the door's own parts (nothing happens on the bolted door;
  it does open the door that swings by itself, state CurveAnimation).
- praydog's cutscene flag (`re8vr.is_in_cutscene`) is "the camera's controller is not the fully controllable one",
  held one second longer; while it is up the loader zeroes the leg solver's centre offset. It goes up for a moment
  whenever a run stops, with no event running `[measured 2026-11-26, n=3 stops; read from RE8VR.cpp, March source]`.
- DEAD END: reading joints in the script's camera step to place the body (two designs; the joints there are not the
  posed body) `[disproved 2026-11-26]`. PrepareRendering post is where the posed body is read.
- A REFramework call on the player object can throw while the prologue's scene is torn down; anything "off for the
  whole run after two throws" then never comes back `[measured 2026-11-26, n=1]`.
- Full write-up: `modding-notes/2026-11-26d-from-zero-step-3-worn-doors-body-legs.md`.
