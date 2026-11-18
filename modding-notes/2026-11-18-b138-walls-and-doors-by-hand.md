# 2026-11-18: b138, the hands stop at walls; doors and gates pushed by the hand (Developer PC, Opus, no game running)

Tefa, after wearing b137: *"in vr, i could not open gates by hand, they still opened by themselves with me quite far away"*;
then *"do the gates fix and if you can at the same time, see if you can get the hand to collide with walls"*.
What Tefa saw was the plain game: the 2026-11-16 door work had only been read on the simulator, nothing was built.

## Built `[compile-verified 2026-11-18]`, installed as b138 (builds store: doors by hand/v0.1.0-b138), NOT RUN
1. **Doors and gates by hand** (`src/doors.cpp`, `doors.h`; numbers `DOORS_*` in settings.h). Visceral RE2's doorpush moved
   onto Village's `app.DoorBehavior` leaves, up to four near the player at once (a gate's two leaves). Whoever opens a door
   (A, the game's own push, the hand), it is drawn **1 degree** open; from there the hands (the drawn wrists) and the body
   push it, never less than the body needs to pass; it goes back down with the game when the game closes it. The game's
   angle is read only on the frames the game itself wrote the leaf (it differs from what we left there), because a Village
   leaf, once open, is no longer written by the game (2026-11-16 note). A hand moving into a shut, unlocked leaf presses A
   for the game: the plugin counts it in bridge slot 266, `re8_vr.lua`'s pad holds Decide for six pad updates (the crouch
   pulse's way). Locked doors get no A (`IsLocked`).
2. **The hands stop at walls** (`lua/visceral_re8_walls.lua` + `src/walls.cpp`, bridge slots 252-265). The Lua casts one
   ray a frame per hand from about the shoulder (camera 18 cm down, 17 cm out) to praydog's hand position plus 5 cm, the
   thrown magazine's ray; a hit becomes a plane handed to the plugin, which keeps the IK target on the player's side of it,
   first in the arm-solve hook (before recoil, the docking, the poses). Keeping it ON the plane gives the same answer however
   often the game solves the arm in a frame. The hand slides along the wall. A gun in the right hand stops with it; the left
   hand docked on the gun is left to the gun. Anything whose name (or a parent's) says door or gate is not a wall.
   Emporium > Comfort: "Hands stop at walls", "...with a gun in the hand too" (both on; walls.json).

## What the first run must show (the log, `[visceral-re8-walls]` and `doors:` lines)
- The game's collision layers, and which one the rays use (`Terrain`-like first, else `Bullet`) `[hypothesis]`.
- The first 20 different things a hand's ray hits, by name: are they walls, or also enemies, props, the player's own gun?
- Whether `getContactCollidable` answers (else doors cannot be told from walls: one log line says so).
- At a door: "a door leaf ... away", "a hand on a shut door: A for the game", "the game opened a door: drawn at 1 deg",
  then "a door drawn at N deg". If the game's own open is still seen at full swing, the joint is written after our points.

## Open questions
- `DOORS_LEAF_M` 1.3 m is a guess for the gate's leaves `[hypothesis]`.
- Aiming with a gun stopped at a wall: the shot may still come from where the controller is (praydog's aim).
- The game opens gates from far away (Tefa); now they only crack 1 degree until pushed. Whether the body can still walk
  through a 1-degree gate (as in RE2, where the game's collision follows its own angle) is for the first run.

## The simulator run, same evening: b139 `[verified-live 2026-11-18, simulator, n=1 each]`
- **The gate:** walking up to the Duke's gate, the game swung both leaves open by itself (what Tefa saw: the game's own
  push, 8 then 51 degrees); both were held at **1 degree**. Ethan's body in the gateway pushed one leaf to **17 degrees**,
  the left hand swept forward pushed the other to **41 degrees**. The right hand down the middle touched neither leaf.
- **The walls, two faults found and fixed in b139:** (1) the `Terrain` layer hits nothing (a ray straight down from the
  head: Terrain 0 hits, Bullet 1, Default 8): the rays now use `Bullet`, the thrown magazine's; (2) the plugin's freshness
  check used `bridge::has()`, which calls anything from 499 up "no value": the frame count passes that within seconds, so
  the wall stop stood down every frame. Fixed: plain finite checks. With both fixed, the right hand stopped at the
  mausoleum wall (`st10_167_MausoleumArea_Etc`), 7-12 cm short of where it would have gone, bare-handed and with the LEMI.
- The gate's leaves are named `Door` under `sm81_077_StudioGate_00_DoubleDoor_BreakLock`: skipped as walls, as meant.
- While a save loads the hand sits ~130 m away: a 1.5 m reach cap now.
- Test trap: a VR Bench controller held perfectly still goes "asleep" after 20 frames (sleephands.cpp) and the hand drops
  to the hip; `tools/sim/hands_live.py` holds the pose with a 2 mm wobble.

## b140: the gun's muzzle stops at the wall too `[verified-live 2026-11-18, simulator, n=1]`
Tefa: *"see if long guns also stop at the wall, i mean that even the tip of the gun doesn't go in the wall and bends with
the hand naturally inwards"*. `visceral_re8_walls.lua` learns where the muzzle sits in the right hand's own frame (last
frame's drawn muzzle against last frame's hand as walls.cpp moved it, eased), predicts the muzzle from where the player
holds the hand now, and casts hand -> muzzle; a hit gives the hand a stop plane moved back by the gun's own length, so the
muzzle stops 3 cm off the wall and the hand gives way (the arm bends; the docked left hand follows the gun). The hand's own
plane and the muzzle's: whichever needs the hand further back wins. walls.cpp's push limit 0.6 -> 1.2 m (a rifle's length).
On the simulator, F2 aimed level at the mausoleum wall from a hand 0.55 m out: "the right gun's muzzle meets a wall", the
hand 48-91 cm back, and a ray from the eye to the drawn muzzle then hit nothing; the same muzzle point on 5 samples (no
flicker). Open: a hand sent back this far may look odd up close (a real arm would raise or tuck the gun): Tefa's look
decides whether it wants a tilt instead past some distance. The gate's leaves are not walls, so a muzzle passes into them.

## b141: the gun turns at the wrist instead; the gun pushes doors `[verified-live 2026-11-18, simulator, n=1 each]`
Tefa: *"instead of pushing the hand back, can right hand stay put and the weapon angle away from the wall and the hand at
the wrist just follows. and is it possible to use a gun to push a door open"*.
- **The tilt:** on a muzzle hit, `visceral_re8_walls.lua` finds the smallest turn (2-degree steps, up to 80) of the barrel
  away from the wall and a little up (the wall's normal across the barrel, plus half of "up" across it; a head-on wall:
  straight up) that keeps the muzzle 3 cm off the wall; eased in at 720 deg/s, out at 240. The turn goes through bridge
  267-271 to `walls.cpp`, which puts it on the right hand's IK target rotation (before it), once per placing of the target
  (a target that already carries the turn it wrote is left alone, since the game can solve an arm twice a frame). The hand
  stays put; only past 80 degrees does it also slide back for the rest.
- Found on the way: `re8vr.last_right_hand_rotation` is NOT unit length (e.g. -0.36 -0.63 -0.48 1.00); normalised before
  use (b140 learned and predicted with it unnormalised; its test passed regardless). A copy of the script loaded again by
  hand (dofile) now takes over from the old one (`__visceral_walls_gen`).
- Simulator, F2 aimed into the mausoleum wall three ways (controller yaw -180 / -165 / -150): muzzle in the wall "no" each
  time (`tools/sim/q_muzzle_wall.lua`), the hand moved 0.00 m, the gun turned 46 / 54 / 38 degrees, pitched up.
- **The gun pushes doors:** the drawn muzzle (bridge 272-275) and the barrel's middle push leaves like the wrists (5 cm reach)
  and can press A on a shut one. With the hand held still by the body, sweeping the rifle across pushed a gate leaf from 40
  to 50 degrees (`tools/sim/q_gate_leaves.lua` reads every near leaf's angle).
