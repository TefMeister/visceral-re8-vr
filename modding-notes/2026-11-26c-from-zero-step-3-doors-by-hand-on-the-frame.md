# 2026-11-26c: from zero, step 3: doors by hand, on the frame (/pd, Fable, Build PC)

Board rows RE8-087 and RE8-088. **The game was not launched; nothing here has been run.** Everything is in
`dev-archive/rebuild2/`. Builds store: `rebuild 2/v0.1.0-b179` (what Tefa wore up to 14:11), `b180` (the Rose check
in the frame), `b181` (doors); b181 is installed.

## 1. What Tefa asked (2026-11-26)

- *"pushing doors open by hands, the only thing is walking with rose to the very first door, i cannot use my hands so
  the door must open with me just walking into it"*.
- *"the door cannot have the normal 'open' sound, that plays when A is pressed or the door swings open just a tiny
  bit, it must only have the sound of the hinges ... we must mute the sound that is the first, door is now partly
  open sound"*.
- The plan (walk-near off except with Rose; a hand on the door opens it; the leaf follows the hand and the body; the
  knob sound muted, every sound switchable; locked and already-open doors left alone): **"16 yes"**. A hand hanging
  at the hip that brushes a door he walks into opens it: **"17 yes"**.

## 2. The door's sounds: what the game has

Read from `re8.exe`'s own type database with no game running (new tool: `flat-to-vr-RE-toolkit/tools/tdb-read.py`).

- The reader is right about this exe: the eight door-state numbers it prints (Closed 474011919, LittleOpened
  171654102, Opening 887278378, Opened 3232296810, Push 396010129, Closing 3360157036, Locked 3401490761, External
  2304963444) are the eight read in the running game on 2026-11-19 `[verified-numerically 2026-11-26, 8 of 8]`.
- `app.DoorBehavior` plays its sounds through `CallSE`, in two forms: `CallSE(app.DoorSeTriggerType.Value)` and
  `CallSE(System.UInt32)`; plus `CallSEFromOutSide(uint, bool)` and `CallSEFromOutSide_Unlock(bool)`
  `[inferred-static 2026-11-26: the method list]`. That these are the ONLY way a door sound starts is not
  established (the player's own "open door" action may play a sound of its own).
- `app.DoorSeTriggerType` has exactly ten kinds `[inferred-static 2026-11-26]`, name = murmur hash:
  Locked 3401490761, CreakSlow 1884312664, CreakStop 3741696246, **OpenKnob 3881480549**, OpenLock 3567993302,
  OpenSlow 165766960, CloseCreakShort 2057132247, CloseCreakLong 2638778551, Close 1212689092, CloseSoft 3119021430.
  `Value` is a class (parent System.Object) with `V` (int) and `H` (the hash); the ten live in static fields.
- **Which kind is Tefa's "first, partly open" sound is NOT known.** By its name it is OpenKnob `[hypothesis]`; the
  hinges would be CreakSlow / CreakStop, perhaps OpenSlow. Tried and not conclusive: the hash numbers appear as code
  immediates only in the type's static constructor (`re8.exe+0x2374050`), so the door code uses the objects, and
  "which state calls which sound" cannot be read off the immediates.
- Related fields on the door: `RequestCallSe`, `CallSePlayer`, `OpeningDoorSeEndType`, `CallOpenEndSe`,
  `ClosingDoorSeEndType`, `CallCloseEndSe`, `IsPushDoorCreakSe`, `AfterSECall`, a `WwiseContainer`.
- ⚠️ A correction to b178: its "LittleOpen = 3407536511" is no state. The real names are LittleOpening
  (2329368004) and LittleOpened; there is also CurveAnimation (4118602539). b178 therefore never saw the
  "starting to crack open" state `[inferred-static 2026-11-26]`.
- Also there, not used yet: request names (`app.DoorRequestStateChangeNames`: RequestOpenState, RequestLittleOpen
  State, **RequestEnableHandTouchState / RequestDisableHandTouchState**), `IsHandTouch`, `RequestDoorAngleSet(float)`,
  `get_doorBottomCenter()`, `PushSensorColShape`.

## 3. What was built (b181) `[compile-verified 2026-11-26]`

New pieces of the frame:
- **`gate.cpp`: the request gate (rule 5).** Parts ask; requests are made on the main thread at one point
  (UpdateBehavior pre, right after the player is found), never with no player, once per ask, counted per kind in the
  log every minute. First kinds: `door-open`, `door-solid`.
- `base`: `dyn_ptr` / `dyn_value` (a checked call on an object whose type is only known when met: the scene's
  component list), `field_data`, `rotate`. `tests/mathtest.cpp` compiles the shipped `base.cpp` and checks `rotate`
  against the rotation matrix and the leaf rule "at yaw t the leaf lies along (cos t, 0, -sin t)"
  `[verified-numerically 2026-11-26]`; `build.sh` runs it at every build.
- `jointwriter`: a new owner, `DoorLeaf`.
- Hooks: four game functions are hooked now (was one). The three new ones only read a flag or their own argument
  and add to a counter (rule 8); the frame step does the logging.

`doors.cpp`:
1. `app.InteractDoor.OnOverlapDoorPushCollider` is skipped, so nothing opens by walking near; it is let through
   while Rose is carried (`gamearms::carrying()`) or the headset / controllers are not in use.
2. The nearest four `app.DoorBehavior` within 3 m are looked after (looked for every 0.5 s). The leaf's side and
   width come from the door's `get_doorBottomCenter()` (read as a world point or as a point in the door's frame,
   whichever is plausible; the log says which); if neither, both sides count and the leaf is 1 m.
3. A hand joint (`L_Hand` / `R_Hand`) within 10 cm of a Closed leaf's face and moving toward it asks the gate for
   `InteractDoor.StartInteractDoor(player)` on the `InteractDoor` part nearest Ethan (within 1.6 m of the hinge).
   No height limit (Tefa's yes to the hip hand). Locked: a log line, nothing asked. 1.5 s between asks.
4. When a door seen shut goes into an open state with the hands free it is ours: drawn at rest + 1 degree, pushed by
   the hands and the body (b178's angle sums), written through the joint writer; its `via.physics.Colliders` (the
   leaf's and its children's, not the `Collider*` sensors, not the AiMap ones) are switched off through the gate,
   and back on when the game's state is Closed for 0.3 s. A door that opens while the game's arms show is the
   game's own until it is shut again. A door found open is left alone.
5. `doors.txt` in the data folder: the hand's reach and the body's reach in cm, read every 2 s.

`doorsounds.cpp`: both forms of `CallSE` are pre-hooked. The object form compares its argument with the ten
objects' addresses (found on the main thread, each checked by its hash at +0x14 before it is trusted); the number
form compares the hash. A kind on the mute list is skipped. Default list: OpenKnob. `doorsounds.txt` in the data
folder (kind names, any separators) replaces the list live. Every kind is logged when it plays or is muted:
`door sound: OpenKnob (MUTED; 1 so far)`.

Switches (off.txt): `doors`, `doorsounds`, `gamearms`.

## 4. RE8-088, done with it

- The carry check and the scene list are `gamearms.cpp` now; `visceral_re8_game_arms.lua` is out of the game folder
  (moved to the backups by the installer) and in `rebuild2/archive/`. The plugin writes bridge slot S_GAME_ARMS;
  `re8_vr.lua` asks `__visceral_re8_bridge.game_arms()`; the disproved body-IK try (`__visceral_re8_game_body`) is
  out of `re8_vr.lua`. The head try is carried over as it was (it logs what it finds).
- The builds store: **the series number stays 0.1.0 on purpose.** `builds.py` finds builds by `v<series>-b`, so a
  new series number (the design note's `v0.2.0`) would hide b001-b178 from `list` and `restore`. Rebuild 2's builds
  are in the feature folder `rebuild 2`, carrying on from b179; `builds.py list` still ends ... b177, b178, b179.
  PROJECT.conf says so.
- `install.sh`: a third word `keep` in files.txt = put in only when the game folder has none (Rose's carry pose,
  `data/carryarms-rest.txt`); a file an earlier install put in and the list no longer names is moved to the backups.
- `deployed.sh` record replaced with the eight files of the new install (8 of 8 match).
- NOT done: the recorder (`visceral_re8_carry_rec.lua`) stays until the prologue is done.

## 5. A fault of mine, found and cleaned the same hour

This clone checks text out with CRLF. `install.sh` read `files.txt` raw, so every target name ended in a carriage
return: five copies with that broken name were written beside the real files (the real ones untouched), and a
half-made b180 landed in the builds store. Cleaned: the five copies removed, the uncommitted b180 folder removed and
INDEX.md put back, `install.sh` now strips carriage returns from every list it reads, reinstalled, the folder check
passes. Rose's kept pose and the config file were compared with b179: unchanged. On the fault list as fixed.

## 6. What is NOT established

- Everything in section 3 at run time: none of it has run. In particular:
  - whether an ordinary house door answers `StartInteractDoor` like the Duke's gate did (it has never been seen),
    and whether it locks Ethan into a motion;
  - whether the walk-in open works with Rose once the hook is in place (the hook lets it through, by design);
  - whether a write of the leaf joint after PrepareRendering shows, and whether the game fights it (b178 wrote at
    two other points);
  - the leaf's side / width reading (`get_doorBottomCenter` is a guess at a useful source);
  - whether `CallSE` runs for every door sound, which form the game uses, and whether skipping it has side effects;
  - which kind is which sound. A sound counted twice (once per form) means one form calls the other.
- A door opened by an enemy or by a real A press is taken like any other open door (drawn at 1 degree, pushed).
- `gamearms.cpp` has not run: the Rose hold, the body in the crib scene and on the stairs must be seen again.

## 7. The first run (/ms): what to look for in the log

`[visceral-re8] doors:` and `door sound:` lines.
1. Start: "no open by walking near any more", "door sounds: the door's sound call is watched (by object: yes, by
   number: yes)", then "all ten kinds are known by their objects", "muted now (the built-in list): OpenKnob".
   `game arms: the game's arms, carrying Rose`.
2. Walking to the bedroom door with Rose: "a door N m away: its leaf is W m wide, side S"; the door opens by
   walking in; "a door opened while the game's arms show: left to the game". Which `door sound:` lines came, and
   what Tefa heard, names the kinds.
3. After the crib, a shut door: "the left / right hand on a shut door" -> "the game was asked to open it" -> "the
   game opened a door ... drawn at 1 deg" -> "N solid part(s) off" -> "a door pushed to 15 / 30 ... deg" -> "the
   game shut the door".
If the derivation is wrong rather than a number needing a tune: no "a door N m away" line at all (the scene's
component list is not what `get_Count` / `get_Item` answer on); "by object: NOT FOUND" (the overload names); a hand
through the door with no "hand on a shut door" line while the leaf line shows side 0 (the frame's axes are not the
gate's).
