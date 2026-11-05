# Resting hand poses for the docked hands, cut from the game's own takes (2026-11-05, Fable, home PC, flat)

Tefa's pick from the Fable list: *"resting hand and finger poses on our docked hands"*. The moving parts of a reload already
play as clips (2026-11-04); this is the still pose a docked hand rests in between them, per gun and spot.

## What was there

Hand Poser holds a left-hand finger pose per gun and spot from `reframework/data/hand_poser/guns/<gun>_Inventory[ @ <spot>].json`
(and the window's own copies). Of the 66 files, 52 were copies of one another or of `no gun.json` (hashes checked): the LEMI's
five were all the "no gun" pose; the pistols shared one set copied on 2026-11-01 12:55. Only 14 were one of a kind.

## What was built

`dev-archive/native/tools/make_rest_poses.py` reads the 2026-11-02 finger takes (local, 89 MB, game animation data) and writes
one Hand Poser file per gun and spot, in the engine's own Euler angles:

| spot | the frame |
| --- | --- |
| the gun's own pose, `@ handle` | the middle of motion 2100: the two-handed hold after a reload (the draw_idle takes of the guns put in hand by `equip` only show the relaxed curl, 31/29 deg) |
| `@ magazine`, `@ insert point`, the GM 79's rounds | the fullest left grasp inside 2500 that the hand lets go of again (LEMI 70 deg at 1.21 s; the F2's magazine is wide: 39 deg under a 48 deg hold) |
| `@ slide` on the pumps and the Rocket Pistol | the grip inside 2513 that works the pump, after the shell is let go (M1897 69 deg; the W870's is its 47 deg hold) |
| `@ rounds from the pouch`, `@ slide from the left` (the shell port, spot 8) | the first frame of a 2512 cycle: a round in the hand |
| `@ drum` (revolvers) | mid-2512: the left hand holding the gun by the cylinder |
| `right hand on the cover` (revolvers) | the right hand at a 2512 cycle's start, a round about to go in |
| `right hand on the bolt` (F2) | the right hand's fullest curl in the first 1.2 s of 2500 |

Borrowed (no game source): the pistols' and long guns' `@ slide` / `@ slide from the left` use the W870's pump hold (no reload
puts the left hand on a slide), and the revolvers' left `rounds from the pouch` is the W870's shell hand (the game loads them
with the right hand). 16 files, listed by the tool; each file's `source` field says where it came from.

Files: 57 written (game folder and the Hand Poser window's folder), 14 of Tefa's kept (one of each family of copies: the
M1911's five, the WCX's own, the W870's own, the M1897's own / slide / rounds, the Wolfsbane's drum and drum + cover,
the GM 79's own and insert point, plus the hammer, which no take covers). All 66 old files: `dev-archive/hand-poses/archive/2026-11-05-before-rest-poses/`.
Three placeholders with no game source taken out (`start 1`, `start 2`, the Rocket Pistol's magazine).

## The engine's Euler angles `[measured 2026-11-05, flat, 12000 samples]`

`via.Joint.get_LocalEulerAngle` / `set_LocalEulerAngle` (what Hand Poser writes) and `get_LocalRotation` were read together
on all 30 finger joints for 400 frames (`lua/archive/zz_euler_probe.lua`). The order is **YXZ: q = qY(y) * qX(x) * qZ(z)**
(the Z turn applied first), median and worst error 0.0000 deg; the other five orders are 0.0005 to 0.08 deg off in the
median and 9 to 25 deg at worst. The tool refuses to write an angle that does not turn back into the take's rotation.

## Checked

- The LEMI's new file loaded in the flat game on a gun change (`own pose loaded: ri3046_Inventory`, no parse error)
  `[verified-live 2026-11-05, flat, n=1]`. Flat, the left hand is not held (not docked), so how the poses LOOK on the docked
  hands is a headset look: `GATE: VR USER`.

## Next

- Wear it: LEMI magazine in hand, W870 on the pump / shells in hand, Wolfsbane drum + round; tune in Hand Poser as before
  (the window reads the live angles, so it starts from these). `MODEL: OPUS`.
- A real slide pose: record the left hand on a pistol slide once (the finger recorder with the hand docked by Hand Poser),
  or let Tefa tune the LEMI's once and copy it by the tool.
