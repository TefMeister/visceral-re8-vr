# 2026-10-24 (evening): /pd on the four no-game rows

`/pd force re8` on the home PC, Opus. **The game was not launched; nothing here has been run in the game.** The morning `/ms`
claim (10:27) was still on the board because the PC was shut down without a write-up; its work (builds 7-11) was all pushed
and is written up in `2026-10-24b-first-wear-grab-palm-clicks.md`. Installed at 17:36 (dll `b22a8c4d`), backup
`/d/RE Village REFramework builds/_backup-2026-10-24-1736-before-visceral-re8-deploy`.

## 1. The loading flood

The 15:36 run's log: 7,568 `System.NullReferenceException` lines between 15:36:02.6 and 15:36:16.7, all from
`app.CharacterUpdater.get_equipController` (5,540) and `app.PlayerWeaponChange.isRequestedBothHandToOneHand / ...ToBothHand`
(2,028), with 22-28 fps meanwhile `[measured 2026-10-24]`. Only Andyalpa's holster, holster visuals and hand gestures scripts
make these calls (none of ours). The installed copies were his originals (line endings only differ).

Fix: the three files are now shipped as our copies in `dev-archive/native/lua/` (as `re8_vr.lua` already was), each with a
small `VRZ` helper: a getter that failed (nil, or a throw caught by pcall) is not asked again for `VRZ.BACKOFF_S` (0.5 s).
Five call sites changed: holster `COMPONENTS.call_updater`, `native_weapon_change_requested`, the `flag()` in
`try_armed_dpad_equip`; gestures `get_equip_controller`; visuals `current_equipped_item_id`. In play these getters answer, so
nothing changes there. A mock run of the shipped helper text (`lua`, 120 fps, getter ready at 3 s): 6 failed asks instead of
360, the first answer on time `[verified-numerically 2026-10-24, n=1]`. All three pass `luac -p`. `build.sh` now ships every
file in `native/lua/` over the pack's file of the same name.

Not established: that the flood causes the black loading hang `[hypothesis]`.

## 2. Stale objects during a load

A null check lets a stale pointer through, and `o->get_type_definition()` or a raw `m->call` on it crashes the game (no
exception to catch). REFramework's own `is_managed_object` (read in `shared/sdk/REManagedObject.cpp`) checks the memory is
readable, then the object's info and class, and that the type points back at itself, so it is safe on a freed pointer
`[inferred-static 2026-10-24]`. It now guards `call_direct`, `field_ptr`, `component`, `type_is`, `overload`, `try_bool`,
`m_of`, `motion_joint`, recoil's `chamber_count` / `has_loaded_ammo` (which read the gun's type with no check at all),
reload's `set_loaded_on` / `magazine_shown` / `mag_part`, and the HUD's `is_type` / `fix_children`.
Left alone on purpose: `invoke` / `call_ptr` and `joints.h`, which are used on joints. REFramework declares `REJoint` as an
`REManagedObject`, but no run has shown a joint passing `is_managed`, and getting that wrong would switch off the reloads.

## 3. The spent shell leaves with the hand

`type_probe.txt` (the plugin's own type dump) has `app.WeaponCore.ejectCartridge()` and `app.PlayerComponent.get_isEjectCartridge`
(a motion event, next to `get_isEventRequestShoot`) `[inferred-static 2026-10-24]`. New `src/eject.cpp`: hooks
`ejectCartridge`; in VR, for the player's pump or bolt gun, the game's call is skipped; a shot marks a spent case as waiting;
the pump's pulled-back click and the bolt's bolt-back click make the same game call, once per shot. Handguns keep the eject at
the shot. Switch: `EJECT_BY_HAND`. Builds 8 and 9 already cut the game's after-shot motion at frame 8, which may have removed
the shell already; nobody has looked since.

What would show it is wrong: `eject: shell thrown by the hand` in the log with no shell seen means the call needs its motion's
state (then spawn it from the `EmptyBullet` joint instead); no `eject: ... skipped` line at all means the shell does not come
through this call.

## 4. The pouch shell follows the right controller

The shell is the gun's own `Bullet` joint, carried in the left hand. Its pose was computed against the gun object and written
as the joint's LOCAL pose, but a joint's local is against its parent joint. The M1897 joint log: `Bullet` local
(0, -0.015, -0.013), `Body` local (0, 0.030, 0.222). Under the root, the shell's rest would be at the grip, so it most likely
hangs under `Body` (or `Carrier`), and every write was off by that parent's place, turning with the gun
`[inferred-static 2026-10-24]`. That fits both reports: "too far from the fingers" and "moves a little with the right
controller". Now written in the world (`set_Position` / `set_Rotation` on the joint, as the falling magazine is), with a log line
naming the parent once per gun. Switch: `SHELL_WORLD_WRITE`. The 7 cm drop Tefa asked for stays; it was asked for while the
offset was there, so it may need retuning with the poser, along with the size.

## Checks

Each change `[compile-verified 2026-10-24]`, no warnings; exports present; the recoil numeric test unchanged (480 frames, worst
3.19e-06). `reload.cpp` is now 810 lines (soft limit 800): a move-only split is on the board.
