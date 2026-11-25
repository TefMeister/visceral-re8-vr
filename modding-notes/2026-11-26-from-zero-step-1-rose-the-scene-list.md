# 2026-11-26: from zero, step 1: the bare base worn, Rose, the scene list (/ms, Fable, Build PC)

Tefa in the headset, 00:00 to 01:50. Board row RE8-081. The base: the stock game + REFramework nightly 01451 +
praydog's VR layer. What went in tonight lives in `dev-archive/rebuild2/` (the new series; `tools/install.sh` is the
only installer, `tools/files.txt` the list of our files, `tools/settings.txt` the settings we change).

## What Tefa saw (his words) and what was done about it

1. **The bare base.** *"the game works well in the headset so far"*; the window fine; *"keep the music as is"*
   (so the music is NOT muted on this install: his call, 2026-11-26).
2. **Cutscene camera.** Wanted: the game's camera turns the view left and right only, never up and down, in
   cutscenes. `VR_DecoupledPitch=true` in `re2_fw_config.txt`. Tefa: *"the cutscene camera worked!"*
   `[verified-live 2026-11-26, n=1]`
3. **Ethan carrying Rose.** On the bare base she hangs upside down from the left hand while both hands follow the
   controllers (his picture, 00:20): praydog's layer, not ours. Tefa: *"the idle pose for ethan when the controllers
   are down goes into the pose where he is holding rose the correct way"*.
   - The carry has NO game event and none of the VR layer's flags `[measured, n=1]`. It runs from the first frame
     of control to the crib event `c10e050_00`. Its marker: the object `pl5000` (Rose) is a first-level child of the
     player's transform (`pl1000`), gone the moment the crib event's motion starts `[measured, n=3 runs]`.
   - Fix: `visceral_re8_game_arms.lua` sets `_G.__visceral_re8_game_arms` while `pl5000` hangs there; our one dated
     line in praydog's `update_hand_ik` (re8_vr.lua) returns early then, the way praydog already does for his
     end-game events. Tefa: *"it works, he holds her right and hands came back"* `[verified-live 2026-11-26, n=1]`
4. **Low hands, menus too low.** Both were fixed in the old build and were back on the bare base.
   - The low hands: `re8_vr.lua` asks `is_openxr_loaded()` once, 26 ms before "Initializing OpenXR"
     (00:53:59.642 against 00:53:59.668) `[measured on nightly 01451, n=1]`: the same race as on the March build.
     The dated block is back in re8_vr.lua (the same logic as b178's).
   - The standing height: `visceral_re8_origin.lua`, written fresh with b178's file as the reference.
   - Tefa: *"menus were at eye level, hands sit right"* `[verified-live 2026-11-26, n=1]`
5. **The body in cutscenes.** REFramework's `fix_player_shadow` (RE8VR.cpp, pre-LockScene) sets DrawDefault off on
   the body meshes when the controllers are not in use OR (its cutscene flag is up AND "Auto Hide Upper Body in
   Cutscenes" is ticked) `[read from the nightly's source + measured, n=1]`. The patting scene on the stairs
   (`ch01_0000_Baby_100_Dandle`) raises the cutscene flag with no event, so the body vanished in it.
   - First: DrawDefault put back on after LockScene while Rose is carried. Tefa: *"body stayed visible in the
     patting scene"* `[verified-live, n=1]`
   - Then the SCENE LIST in `visceral_re8_game_arms.lua` (`SCENES`, keyed by the game's event name): `c10e050_00`
     body = true. Tefa: *"body was shown in the crib cutscene and it looks much better"* `[verified-live, n=1]`
   - Then Tefa's decision: *"please leave the body on as a default for every start now and i'll let you know when
     we come across a cutscene that really is not good and needs the body off"*. `RE8VR_AutoHideUpperBodyCutscenes`
     and `...LowerBody...` = false. The book scene with Mia: *"body was there"* `[verified-live, n=1]`.
     A scene that needs the body off gets a line on the scene list (that half is not written yet).

## The bob while carrying Rose: measured, not fixed

Tefa: walking forward and sideways she swings a lot (*"up to 30cm"*), backward *"is how it should always be"*.
- Tried: the body IK skipped too during the carry (as praydog does in the end-game events). *"bobbing is still a lot
  moving forward"*: off again `[disproved as a fix, n=1]`.
- Tried by Tefa: praydog's "Movement Shake" ticked. *"did not change anything"* `[disproved, n=1]`: the removed
  camera bob is not the cause.
- Measured (recorder v5, 90-frame windows, the left and right hand joints against the eye camera): **6 cm** of
  travel walking forward or sideways, **2 to 3 cm** backward, 0 standing; the head and hip joints do not move against
  the camera `[measured 2026-11-26, n=1]`. (The "Chest" joint name was not found, so the chest was not measured.)
  So it is the walk motions' own hand travel. The eye says 30 cm, the joints say 6: Rose sits close to the face
  and the motions also turn her; the travel of Rose herself was not measured.
- The walk is ONE motion id (layer 0, 0/1): a blend of `Hands_Walk_HoldBaby_Loop`, `..WalkB..`, `..WalkL..`,
  `..WalkR..`. Node weights are read-only (`MotionNodeCtrl` has only `get_Weight`); `TreeLayer` has
  `trySetNodeParameter` / `getNodeParameter` (not tried). Tefa's idea (the backward walk used when walking forward)
  would go through those and is the uncertain route.
- **The route chosen:** the joint writer of the frame holds the hands' height steady during the carry.

## Still open from tonight

- **Empty hands open and close while walking** (Tefa: *"hands animate open/close again when moving with an empty
  hand, both hands do it"*; *"let's do hands as soon as possible"*). The walk motions move the fingers; b178 held
  them through its pose parts. The first job of the frame's joint writer.
- **Ethan has no head in scenes seen from outside his body** (the crib scene; Tefa thinks the ending too). The try
  (FaceMesh / HairMesh DrawDefault on during the scene) did NOT run: `getComponent(app.PlayerMeshController)` on
  `re8vr.player` returned nothing in my script (*"head: no mesh controller"*), though praydog's own script and
  RE8VR.cpp take it from the player. So nothing is established about the head; Tefa: *"maybe it was never there?"*
  Next: find the controller the way praydog's `GameObject.get_component` does, log what FaceMesh and HairMesh are.
- **The crib scene's camera**: Tefa would like it not to take the view at all; "we'll have to see". A per-scene
  camera setting would be a second key on the scene list; the camera code of re8_vr.lua is not read for it yet.
- **DLSS as an option** (asked at the start): praydog's `pd-upscaler` branch is at 8c209b1f (2026-10-11), 13
  commits behind master, so without the start-up freeze fix of 2026-11-17. The route: our own build of pd-upscaler
  with master merged in. Not started.
- The base keeps its cutscene flag up while the controllers rest (seen as a 2-minute "cutscene" after the crib while
  Tefa typed) `[hypothesis, n=1]`: not a fault.
- The recorder (`visceral_re8_carry_rec.lua`, dev only) is still installed. It comes out when the prologue is done.

## What is NOT established

- That any of tonight's fixes holds on a second start or from a loaded save (every one is n=1, new game).
- That `pl5000` under the player is used only for this carry (the ending carries Rose too: praydog's own list
  handles those events; the two were not seen together).
- The frame (design items 1-7) is NOT built. Tonight's parts are three small Lua scripts and dated lines in
  praydog's file; `visceral_re8_game_arms.lua` says where it moves when the frame exists. Rule 11 (per-frame work
  is native) is not met by it yet.
- No build of the new series is in the builds store yet.
