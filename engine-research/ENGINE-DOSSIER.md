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

## Dead ends

- praydog's connector on the 76298bd build (§1). The game's held-trigger shot with only `readyShootByTimer` forced (§2).
