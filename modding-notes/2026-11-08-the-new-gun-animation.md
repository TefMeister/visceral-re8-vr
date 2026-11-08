# The game's own "new gun" animation: found, played on demand, recorded for every gun (2026-11-08, home PC, Opus, flat)

Tefa: *"can you trigger the games 'first time getting a new gun' animation somehow and record it, without me having to
play through the game and find these guns manually?"*, then the idea behind it: *"when finding a new gun in the game,
the game takes over hands and plays the games original animations in front of the player"*.

## What it is `[verified-live 2026-11-08, n=12 guns]`

- The player's action trees (`via.motion.MotionFsm2` on `pl1000`; trees 1, 2 and 9 to 14) hold a step **`Gun.GetWeapon`**
  (and `Melee.GetWeapon`, `Gun.GetWeaponSp`). Its actions: `via.motion.Fsm2ActionPlayMotion` **BankID 0, MotionID 2007**
  and `app.MotionDelegateTagAction` tag `GunGetWeapon`. `Melee.GetWeapon` plays **2006**. Bank 0 is the held weapon's own
  set, so every gun has its own 2007: the W870's is `ch01_0000_Shotgun02_010_GetWep`, 130 frames.
- **Played on demand** by putting motion 2007 on the arm layers 1, 2, 9 and 10 of the player's `via.motion.Motion`:
  `TreeLayer.changeMotion(UInt32 bank, UInt32 id, Single start, Single inter, InterpolationMode, InterpolationCurve)`
  with `(0, 2007, 0, 0..6, 2, 0)`. The arms then do the whole new-gun move in front of the camera (seen in flat: the
  Wolfsbane held in both hands, the drum turned toward the player) and the game takes the layers back at the end.
- What did NOT start it: `app.PlayerMovement.requestUseGetWeapon(app.ItemCore)` (reached through
  `app.PlayerUpdaterFPS.get_playerMovement`; accepted, nothing played: it is probably the game's own request after a
  real pickup), `requestActionExternal("Gun.GetWeapon", 0, 0)`, and `MotionFsm2.setCurrentNode("Gun.GetWeapon", layer,
  nil)` (accepted, the layers stayed on `Gun.ReadyIdle`).
- **The gun plays its own half** (Tefa watched the first pass: *"i did see the animations play, but no weapon parts moved at
  all"*; the takes agreed, not one gun joint moved). The weapon's GameObject has its own `via.motion.Motion` (one layer)
  and `via.motion.MotionFsm2` whose step `GetWeapon` plays the gun's own motion: **Wolfsbane 0, SYG-12 2, every other gun
  3** (`it02_<nnn>_<Gun>_010_GetWep`, the same length as the arms' half; the knife has no gun half). Started on the gun's
  layer 0 in the same frame as the arms, the two run frame for frame. Parts that move: the Wolfsbane's loading gate (Lid
  62 deg), the W870's pump (Slide 10 cm), the GM 79's carrier, the M1897's bolt, carrier and hammer, the pistols' slide,
  hammer and magazine (out about 20 cm), the F2's bolt (80 deg) and magazine, the SYG-12's magazine and slide `[measured]`.
- The first-time flag is very likely `GameRecord_ItemGetOnce` (a name in the program) `[hypothesis]`; not needed to
  play the motion.

## The recordings (local only: the game's animation data)

`D:\claude video game stuff\getwep-takes\2026-11-08\` (README there): one CSV per weapon, every game frame while it
played: the camera and the gun in world space, every player joint (122: world position, world rotation, local rotation)
and every gun joint (local). Frames at about 90 a second:

| weapon | id | frames |
| --- | --- | --- |
| M1851 Wolfsbane | ri3008 | 245 |
| W870 TAC | ri3021 | 169 |
| knife (melee, motion 2006, no gun half) | ri3022 | 308 |
| GM 79 | ri3023 | 179 |
| M1897 | ri3036 | 260 |
| M1911 | ri3040 | 254 |
| F2 Rifle | ri3042 | 313 |
| LEMI | ri3046 | 252 |
| V61 Custom | ri3047 | 317 |
| SYG-12 | ri3048 | 272 |
| S.T.A.K.E | ri3050 | 249 |
| Samurai Edge AW-01 | ri3122 | 250 |

Both halves in every take (the arms-only first pass is kept in `arms-only-first-pass/`).

Not recorded: `ri3051` (the equip guard refuses it: not a gun). The W870 take's hands relative to the camera: the left
hand travels up to 44 cm, the right 22 cm `[measured]`.

## How it was driven (nobody at the keys)

- Flat launch from the exe with `XR_RUNTIME_JSON` pointed at a file that does not exist: REFramework's VR start fails
  (`Could not create openxr instance: -51`) and the game runs flat even with Virtual Desktop streaming.
- `dev-archive/native/lua/zz_lua_repl_probe.lua`: a Lua prompt inside the game through files (`reframework/data/
  lua_repl/in.lua` whose first line is `--seq N`, answers in `out.txt`; global `R` keeps values). Put in for the hunt,
  taken out after. REFramework's Lua here has no `os.remove` and no `sdk.get_tdb`: type names were found by searching
  `re8.exe`'s text (`GetWeapon`, `ItemGet`...) and asking `sdk.find_type_definition` which ones exist.
- Guns into hand: `visceral_re8_finger_rec.lua`'s `equip <id>` command. One start hung in REFramework's hook install
  (threads suspended at boot, never resumed); ended by force, the next start was fine.

## For the VR mod (Tefa's idea, not built)

When a new gun is picked up, let go of the hands (IK and docking off), play 2007 on the arm layers AND the gun's own
GetWeapon motion on the gun, so the game's own move shows in front of the player with the parts working, then hand the
controllers back when the layers return. Board row in
`status/visceral-re8-vr.md`.
