# 2026-11-19: b143, doors open at the hand, not as Ethan walks near (Developer PC, Opus, simulator)

Tefa, after wearing b142 in the morning: *"hands are reacting to walls now! not sure if this is usable in the end, because it is
very finnicky, sometimes the hand goes through a little, sometimnes it stays out too much, but the function works"*, and
*"doors though, i can hear the door opening sound from far away, when the door opened before about a meter or more from
ethan, but when i get close to it, i cannot open it at all, not by pressin A or pushing with my hands. the door opening sound,
it has to come after the hand is actually on the door"*.

## What the b142 log showed `[measured 2026-11-19, Tefa's headset log, kept as village-logs/re2_framework_log-2026-11-19-0859-tefa-b142-walls-doors.txt]`
- "the game opened a door" 1-3 m out, with no hand touch before it: the game's own open (and its sound); doors.cpp then held
  the leaf at 1 degree while the game counted the door OPEN (its own angle 90), so A had nothing left to do.
- The hands did push (drawn 11-37 degrees), never far enough to walk through; the game shut the door after ~30 s; standing
  in the doorway it opened and shut every few seconds.

## Found on the simulator `[verified-live 2026-11-19, simulator, n=1 each]`
1. **The trigger:** `app.InteractDoor.OnOverlapDoorPushCollider` (the leaf's `ColliderPlayerPush` sensor) fires every frame
   the player is in it and calls `RequestStartInteractDoor` -> `startInteractDoor`. Skipping it (pre-hook SKIP_ORIGINAL):
   Ethan stood 1.2 m from the Duke's gate for 30 s+ and it stayed shut. Letting it through again while standing still did
   NOT open it: the game wants the player moving in.
2. **The hand's open:** `app.InteractDoor.StartInteractDoor(player GameObject)` on the leaf's `InteractFront` (the one
   nearer the player) opens it the game's way, i.e. A's path, so the door's sound starts then. On the gate it gave both
   leaves `LittleOpened` (DestAngle +-20).
3. **The door states are murmur hashes of their names** (`via.murmur_hash.calc32`): Closed 474011919, LittleOpen 3407536511,
   LittleOpened 171654102, Opening 887278378, Opened 3232296810, **Push 396010129**, Closing 3360157036, Locked 3401490761,
   External 2304963444. ⚠️ The 2026-11-16 note called 396010129 "shut": it is Push (the walk-in push had put the gate there).
4. **Ethan could not pass a leaf we draw:** the leaf's collision follows the joint we write. `DoorBehavior.SetDoorCollidersEnable
   (false)` did NOT switch the leaf's own `via.physics.Colliders` off (read back on). Switching that component off (and the
   chain padlocks hanging on a gate leaf), keeping the sensors (`Collider*` children) and the enemies' map colliders: Ethan
   walked straight through and his body swung the leaf to 92 degrees.
5. A door left open earlier in the playthrough (the talisman double door, Opened at +-90) must be left alone: the first
   b143 try would have "opened" it at 1 degree. Now only a door seen Closed first is handled.

## Built: b143 (builds store `doors by hand/v0.1.0-b143`)
- `lua/visceral_re8_doors.lua` (new): skips the walk-in push; on the plugin's touch count (bridge 266) with the touched hinge
  (276-278, new) calls `StartInteractDoor` on the nearest InteractFront / InteractBehind; while a near door seen shut is in an
  open state (LittleOpen, LittleOpened, Opening, Opened, Push) its leaf's solid parts are off, back on when it is not.
- `src/doors.cpp`: the door's state decides open / shut (the angle alone missed the game's shut: a leaf stayed "drawn" at
  1.5 degrees); back to the leaf's own resting angle when shut; the turn direction from `DestAngle`; touches no longer press A.
- `re8_vr.lua`: the A press for a touch is gone (an A could also pick something up or start a talk nearby). A real A still
  opens a door the game's own way.

## The final simulator run `[verified-live 2026-11-19, simulator, n=1]`
Hands held down, Ethan walked up to the Duke's gate: shut. Ethan walked right into the gate: his hanging hand brushed a leaf
-> "the game opens it" -> both leaves LittleOpened, solid parts off -> Ethan crossed 5 m to the far side, his body swinging a
leaf -> the game shut the gate behind him (Closing, then Closed), solid parts back on, our leaves back to 0 degrees. The
talisman door (already open) stayed at +-90.

## Open
- A hand hanging at the hip touches a door Ethan walks into: right or too eager? Tefa decides (a height limit is easy).
- The body pushes the leaf only as far as Ethan walks into it; the game now shuts a door soon after Ethan has passed.
- Locked doors: no touch, so no rattle when a hand brushes one. Tefa may want the rattle.
- Not yet seen: an ordinary house door (Village's doors crack open 20 degrees; the gate went to LittleOpened too).
- The walls' finickiness (Tefa: sometimes in a little, sometimes too far out): not looked at yet.

## Second half, 10:1x-10:2x (Fable, /lm, simulator): b144, the walls less finicky `[ID RE8-002]`
Tefa on b142: "sometimes the hand goes through a little, sometimnes it stays out too much".
- **Through a little** `[verified-live 2026-11-19, simulator, n=1 per pose]`: `visceral_re8_walls.lua` stopped only the wrist
  (praydog's hand position = the drawn `L_Hand` / `R_Hand` joint); the middle fingertip (`L_MiddleF3` x 1.15) lies ~18 cm on.
  New: a ray from the STOPPED wrist to the fingertip; a hit sets the hand's plane back by the fingers' reach. First try cast
  from the controller's position, which is inside the wall: a ray that starts inside a wall hits nothing (kept as a lesson).
  Stone wall by the Duke's gate, left hand pushed 35-40 cm past it, each joint's own distance to the surface
  (`tools/sim/q_hand_wall.lua`): flat hand wrist +2.2 / tip +0.6 cm; fingers 40 deg into the wall: tip -8.1 cm before,
  +3.1 cm after (wrist +10.4); fingers 40 deg away: +2.9 / +7.4 (unchanged).
- **Out too much** `[inferred-static; logged once live, not staged]`: the only test was "the line shoulder -> hand crosses
  something", true for a hand reaching round a corner or past a post. New: when that line is crossed, the hand's own path
  (where it was drawn last frame -> where it is held now) must be crossed too; no path yet = the shoulder's word alone.
- Simulator traps found: VR Bench controllers are in ROOM space (a push along -Z only suits head yaw 0; `tools/sim/hand_push.py
  <head yaw>` pushes along the view); `q_wall_scan.lua` falls back to layer 2 when `__visceral_wall_layer` is unset, and layer 2
  shows walls the hand rays (Bullet, 12) do not have: set the global to 12 first. The walker (`walk_to.py`) cannot reach the
  shaman's house door (a straight line, 3 m lower): an ordinary door is still unseen on b143 / b144.
- New tools: `tools/sim/hand_push.py`, `q_hand_wall.lua`, `q_doors_near.lua` (every leaf within 45 m: locked, state, name).
