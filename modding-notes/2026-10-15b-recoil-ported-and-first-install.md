# 2026-10-15 (evening) — Recoil ported to C++, and Visceral RE8 installed on top of the scope mod

`/pd`, home PC, Opus. **The game was not launched, and nothing here has been run in the game.**

## 1. The overlap check (scope mod v1.1.5 against the pack) `[inferred-static 2026-10-15]`

| Scope script | Against | Verdict |
| --- | --- | --- |
| `re8_vrz_reload_guard.lua` | Andyalpa's block gesture in his `re8_vr.lua` (only on while `__vr_lua_heal_override`, set by the holster file) | Fits. Both feed the same `re8vr.wants_block`; the guard clears it at UpdateHID pre (before the pad update that reads it), strips the guard bit after the pad hook, and answers no on `get_isGuardCommandAcceptable`. Andyalpa writes the flag in praydog's update, earlier in the frame, so the guard still has the last word. |
| `re8_vrz_begone_grip.lua` | Andyalpa's `__re8_arm_ik_update_override` (the holster's medicine keep-IK) and hand gestures | Fits in practice. The grip acts only with the sniper rifle out and docked; the override only while medicine is being used, when the rifle is put away. Both write `re8vr.was_gripping_weapon` with the same meaning (left hand on the gun). Watch: healing with the rifle drawn. |
| `re8_vrz_rifle_steady.lua` | the recoil | Fits. The steady measures the barrel in the HAND's frame and turns the right IK target by small (< 6°) in-hand turns; the recoil moves the IK target itself, so the barrel moves with the hand and the steady does not see it. They compose. |

Also taken out of our `re8_vr.lua`: Andyalpa's debug-log block that wrote to a fixed path on his own PC (dead here).

## 2. Install: `build.sh --deploy` / `--undo`

- `--deploy` builds, then installs the plugin, our bridge / menu / `re8_vr.lua` / jitterlog, and every pack file **not
  yet ported** (ported ones are kept out and, if found in the game, moved into the backup). Saved settings
  (`reframework/data/...`) are only filled in when missing, never overwritten.
- Every file it replaces is copied first into `D:/RE Village REFramework builds/_backup-<time>-before-visceral-re8-deploy/`
  with `ADDED.txt` listing what it added. `--undo <that folder>` reverses one deploy. Three were made tonight
  (22:02 first install, 22:16 recoil, 22:17 a one-line lock fix): undo 22:17, 22:16, 22:02 in that order to get the
  plain scope mod back, or reinstall the v1.1.5 zip.
- The pack files went in with Windows line endings where git converted them (`core.autocrlf`): byte-different from the
  `.rar`, same content; Lua and JSON do not care `[inferred-static]`.

## 3. Recoil, port step 2

`src/recoil.cpp` (634 lines) is `re8_vr_recoil.lua` function for function: the shot hook on `app.WeaponGunCore.shoot`,
the kick (per-weapon intensity × global, one/two hands, class profile, full-auto scale, stack cap), the quarter-sine
attack, the damped spring with sustained and settle damping and its four channels, the 45 ms fade-out, and the IK patch
in `app.AnimIK2Bone.calc` (right hand kicked, left hand kept at its place relative to the right when it supports the
gun, with the three fall-backs for where the right hand was). Camera-shake skip kept (off by default).

New support files: `player.cpp` finds the player, its updater, the two hand IKs (`PlayerHandTouch.HandIK[0]/[1]`), the
animation and the equipped weapon exactly the way praydog's `RE8VR.cpp` does, so they are the objects `re8vr` holds;
`json_mini.cpp` reads Andyalpa's saved file. The menu (`visceral_re8_menu.lua`) keeps his "Weapon Recoil" menu, its
first-run defaults, its saving and the overlay hook-up; the plugin re-reads the file when it changes. The bridge
carries four new readings: `re8vr.can_use_hands`, `re8vr.is_reloading`, his aiming check, and seven other mods'
globals as bits (none of the pack's own files sets them).

Differences from the Lua, all `[inferred-static]`: a steady clock in doubles (the Lua's fallback was `os.clock`); the
plugin's own frame count; the unused ammo-delta bookkeeping left out; a negative joint index treated as "not found";
one lock round the state because C++ hooks can run off the game thread; the two globals it published are not
published (nothing reads them).

**Tested against the original** `[verified-numerically 2026-10-15, n=480 frames]`: `tools/recoil_test/run.sh` builds
`recoil_test.cpp`, which compiles the shipped `recoil.cpp` whole (only its clock and random source swapped), and runs
Andyalpa's untouched Lua file through the same four shot sequences (handgun one hand, shotgun two hands, full-auto
rifle burst, magnum at 60 Hz); every pitch, yaw, lift and fade value agrees within 3.2e-6 relative. It also reads his
shipped `re8_vr_recoil.json` through `json_mini` (30 keys, 27 weapons, M1911 1.22, matching Python's reader).
**Not covered by the test:** the IK patch maths, the gates (two hands, zones, reloading) and anything that needs the
game's objects.

**Found by the test, in the original too:** with two hands, or on the full-auto rifle, the kick's muzzle climb (pitch)
is snapped to zero on its first spring step, because the pitch channel's rest threshold (0.007 rad) is bigger than
those kicks (two-handed shotgun ≈ 0.006). Only the sideways turn and the lift remain. Andyalpa's numbers, kept as they
are; if Tefa wants climb with two hands, the fix is that one threshold in `settings.h` (`REC_CH_PITCH`).

## 4. What the first launch must show (flat is enough for most of it)

- `[visceral-re8] recoil: hooked app.WeaponGunCore.shoot` and `... hooked app.AnimIK2Bone.calc` (NOT FOUND = a name is
  wrong in Village).
- `recoil: settings read (on 1, intensity 2.00, 27 weapons)`.
- In the headset, a few `recoil: kick #N ri30xx_Inventory (handgun, one hand) ...` lines when shooting, and Tefa sees
  the hands kick. No kick lines while shooting = the shot hook or the player-gun match is wrong; kick lines but no
  visible kick = the IK hook does not see the player's hands.
