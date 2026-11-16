# 2026-11-16: Village's doors, what they are made of (Developer PC, Opus, simulator)

Tefa: doors pushed by the hand "and re8 as well if you can, although re8 doors work differently" (RE2 b215 / RE3 b025 built
the same day: `visceral-re3-vr/modding-notes/2026-11-16-doors-by-hand-sh2-vs-re.md`). Read live on the simulator from the
last save (Ethan at -0.71 -40.31 108.51) `[verified-live 2026-11-16, simulator, n=1 door each]`:
- Two kinds: `app.DoorBehavior` (47 in the loaded area) and `app.DoorDoubleBehavior` (17). `IsLocked()` answers per door
  (the three nearest were locked; A on a locked one = a 0.8 s state change and a 0.2-degree rattle of the leaf).
- A single door: joints `root`, `_00` (the leaf, `DoorJoint`, `MotionDoorJointIndex` 1); children `ColliderPlayerPush`,
  `ColliderPlayerIn`, `ColliderPlayerPassed`, `InteractFront`, `InteractBehind`, `DoorAiMapCollider`; a `RigidBodySet`.
- `app.DoorBehavior` already has what we want, unlike RE2 / RE3: door states Closed, LittleOpen, LittleOpened, Opening,
  Opened, **Push**, Closing, Locked (`Update...` methods), `get_littleOpnedAngle` = **20 degrees** (the game's own crack open),
  `NowAngle`, `DestAngle`, `IsPushed`, `IsPushFromClosed`, `AddPushSpeedRate`, `PushSensorColShape`, **`IsHandTouch`**
  (true on this door), and an angle override: **`IsOverrideAngle` / `OverrideAngle`**. Setting the override on a SHUT door
  did nothing (`NowAngle` stayed 0): it is presumably read only in the open / push states. Not yet tried with the door open.
- `RequestStartInteractDoor(GameObject, InteractDoorAfter, bool x4, float)` called from script did nothing with Ethan 10 m
  away; with Ethan warped beside an unlocked door (the player's `via.physics.CharacterController` `warp()` after
  `set_Position`; a plain `set_Position` is undone), VR Bench's A did not open it on the simulator (two tries).
- So for Village the plan can lean on the game's own door: open it (A / the hand), and set `OverrideAngle` from the hand and
  the body each frame while it is in its little-open / push states, instead of drawing the joint ourselves.
NEXT: one run at an unlocked door the player really walks up to (first headset or a walked simulator route), to see A open it
and whether `OverrideAngle` moves the open door. `MODEL: OPUS`.

## The Duke's gate, used for real (17:2x; Tefa: "the duke's spot behind ethan has an unlocked gate, about 15m up the steps") `[verified-live 2026-11-16, simulator, n=1]`
- `sm81_077_StudioGate_00_DoubleDoor_BreakLock` (an `app.DoorDoubleBehavior` holding two child `Door`s, each an
  `app.DoorBehavior`, plus chain padlocks). Ethan walked there by `tools/sim/walk_to.py` (the left stick only; the view
  turned with the simulator's head, since the right stick's turn overshoots by hundreds of degrees): 15 m, up the steps, 8 steps.
- **A opened the left leaf all the way, 0 -> 90 degrees in ~1.6 s** (states 396010129 shut -> 887278378 opening -> 3232296810
  open; `DestAngle` -90; `NowAngle` stayed at its shut -1.4). A gate opens fully, unlike a door's 20-degree crack.
- `IsOverrideAngle` / `OverrideAngle` changed nothing in the open state either (as on a shut door): presumably read only in
  the push states.
- **Our own write of the leaf joint (`DoorJoint`, `_00`) at LateUpdateBehavior + BeginRendering held it at 20 degrees**, and
  after we stopped it STAYED at 20: once open, the game no longer writes the leaf. So in Village the game's own angle cannot
  be read back from the joint while we draw it: the door's STATE (shut / opening / open / push / closing) has to tell us
  when the game opens and closes it (state hashes to name first).
- The leaf lies along the hinge's local +X (sound points at x 0.5, mesh centre x 0.41-0.44): `LEAF_SIDE` +1, as in RE3.
NEXT (Opus): port `doorpush` to Village's plugin using the door's states and `DoorJoint`; the touch-A through `re8_vr.lua`'s pad.
