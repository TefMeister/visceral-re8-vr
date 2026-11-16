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
