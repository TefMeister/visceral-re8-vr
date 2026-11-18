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
