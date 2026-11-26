# 2026-11-26b: from zero, step 2: the frame worn, Rose steady, the body made right (/ms, Fable, Build PC)

Tefa in the headset, 11:10 to 14:25, about fifteen short runs, each a new game up to the crib. Board rows RE8-081,
RE8-082, RE8-086. Everything is in `dev-archive/rebuild2/` (the frame `native/`, the scripts `lua/`, the tools).
The logs of every run are kept on the Build PC (not in the repo): `~/visceral-kept-logs/re8-2026-11-26-*.txt`.

## 1. The frame's first run

- It starts; the still fingers hold both empty hands. Tefa: *"it started, fingers stay still on both hands and
  everything looks great"* `[verified-live 2026-11-26, n=1; held in every later run of the day]`.
  The joint writer: thousands of joints written a minute, 0 refused, in every run `[measured]`.
- One crash, at the title screen 16 s after the start, the first start of the build with `sleephands`:
  `c0000005` at `re8.exe+0x432560F` (RCX = 0), in one of the game's own worker threads
  (`re8+0x425DBC5 -> +0x434FC58 -> +0x434FBFA -> +0x4357402 -> +0x432560F`), none of our code on that thread. The
  same build started cleanly right after and five more times that day. `[measured, n=1 crash in ~15 starts]` Not
  the address of 2026-11-25 (`+0x4151C23`). Cause unknown; on the fault list. Log and dump kept
  (`re8-2026-11-26-1258-crash.txt / .dmp`).

## 2. Rose steady: `carryarms`

- Measured first (recorder v7, joint heights against the eye camera, 40 windows of 180 frames): hip, spine, neck,
  head, shoulder 0 cm; upper arm 1; forearm 5 (left) / 3 (right); hand 6. So the swing is the walk motions' arm
  travel from the shoulder down `[measured 2026-11-26, n=1 run]`.
- Rose (`pl5000`) hangs on Ethan's `L_Wep` joint (`get_ParentJoint`), not on a motion of her own `[measured]`.
- The part: while the game's arms show and no cutscene runs, the eight arm joints (shoulder, upper arm, forearm,
  hand, both sides) are held at the pose read once when the player stood still and the arms were quiet for 30
  frames; eased in and out over 0.3 s. With it: hands 0 cm, Rose under 1 cm `[measured, n=1 run]`. Tefa: *"Rose is
  in the crib, steady now in hands while i walk with her"* `[verified-live 2026-11-26, n=2 runs]`.
- A miss found the same day: a run in which Tefa walked off without standing still never read the pose
  (*"bobbing is back when carrying Rose"*). The pose is now kept in the data folder (`carryarms-rest.txt`; a copy
  in `rebuild2/data/`) and used from the first frame. Tefa: *"bobbing gone"* `[verified-live, n=1]`.
  ⚠️ `install.sh` does not put that file into a fresh game folder yet: a fresh install needs one stand-still.
- Tefa: the patting scene on the stairs *"ends with a little jump to me seeing more of Ethan's coat and then jumps
  to the gameplay ... this is a minor thing"*. Not looked at. Whether it was there before `carryarms` is not known.

## 3. The body: `bodyturn`, the walk, `spinestill`, the body's place, steps

Tefa's words, in the order they came, decide the design; each was worn before the next:

1. *"when walking the body is 'glued' to the headset and turns exactly as i look ... walking forward must follow
   hmd direction not where the body is facing"*; of b178: *"Ethan walked in the direction of where the body was
   facing, not where i was actually looking"*. On the bare base, standing still the body does not follow the head;
   walking it snaps to it and stays glued (his words).
2. **The lever** (b178's, proved on the simulator 2026-11-10): a post-hook on `app.PlayerMovement.destinationAngle()`
   returning our own yaw in degrees. Now native (`bodyturn.cpp`, the frame's first game hook), fed by two yaws from
   the bridge script. `[verified-live 2026-11-26, Tefa, n=6+ runs]`
3. **The walk follows the head:** the game walks along the BODY, so the left stick is turned by (head - body) at
   the base script's `set_AxisL` (one dated block in `re8_vr.lua`). The first sign was wrong (Tefa: *"when i look left
   ethan seems to move diagonally more to the right"*); the other one: *"working"* `[verified-live, n=1; kept since]`.
   The formula that is right: `(x cos a - y sin a, y cos a + x sin a)`, a = head - body in the `atan(f.x, f.z)` measure.
4. How the body follows, tried in this order: a free zone of 35 degrees with a slow zone to 60 (*"working"*, then he
   wanted smooth); always following with 0.25 s lag (*"B i think"*); **a dead zone, then all the way to the head
   with a small lag**: 10 degrees (*"it feels good"*), then **25 degrees: "this is really good now!"**. Lag 0.18 s.
   Those are the defaults now. `bodyturn.txt` in the data folder overrides both in play (read every 2 s).
5. Tefa sat down for a "turn your whole self" test; it settled that the hands are right: nothing of the hands was changed.
6. **The stomach turned with the head.** Measured (recorder v10, 45 lines, head -15 to +19 degrees off the body):
   `Spine_0` turns about the up axis by half the head's angle off the body and `Spine_1` the same amount back;
   `Spine_2`, the neck, the hip do not change `[measured 2026-11-26, n=1 run]`. `spinestill.cpp` takes the half
   angle out of both. Measured after: `Spine_0` -2, `Spine_1` 6 whatever the head angle `[measured, n=1 run]`.
7. **The body hung on the headset** (*"following every little move the head makes"*, *"everything moves with it,
   legs hands and body"*). Why `[read from the loader's source, RE8VR.cpp update_body_ik]`: every frame the loader
   sets `via.motion.IkLeg`'s centre offset to (camera position - the body's own t-pose head joint), plus a shift
   along the camera's flat direction when looking down. The lever: `re8vr:update_body_ik(rotation, position)`
   called again from the bridge script right after the loader's camera fix, with a position we keep (the later call
   stands). What that position is, after five rounds with Tefa:
   - it follows the NECK, not the eyes: the eyes are about 9 cm in front of the axis the head turns on
     (`neck_cm = 9`, added behind the head's flat direction BEFORE the follow; added after it, the body leaned the
     other way at once: Tefa, *"i look down left and the whole body posture leans right"*);
   - a damped follow (slow start, catches up, lands softly), `follow_s = 0.9`; a dead zone of `dead_cm = 1`
     (*"this feels right"*, after 3, 6 and 15; 8 cm with a plain ease was rejected before the neck was in);
   - `back_cm = 2` behind the BODY (the rotation is turned back by head - body before it is used and handed on,
     which also keeps the loader's look-down shift from swinging with the head). Neck 9 + back 2 is the
     *"10 body backwards is ideal!!"* (asked for as "just the torso"; what moves is the hips and all above them,
     the feet stay planted).
8. **Steps instead of sliding** (*"feet just drag along the floor ... he just slides on the floor following the
   headset"*). Why `[read, re8_vr.lua's UnlockScene block]`: the loader's script moves the standing origin toward
   the headset and SETS the player's position by the same amount every frame. Instead (`room_step`, the loader's
   block asks it first): up to 12 cm the player is not moved; past it, with the stick at rest, the stick is pushed
   toward the headset (in the headset's own right / forward, then through the same turn as a real push), so the game
   walks him with its own motions and collision; each frame the standing origin moves toward the headset by as far
   as the player really went. Stops within 6 cm, gives up after 1.5 s. Push 0.5: *"a dash almost"*; 0.3: *"still too
   fast"*; **0.18: "that is great"**. The way off is measured at the neck (a head turn alone set off a step:
   *"the body smoothly but quickly jumps to the opposite side"*). 17 steps in one run, none blocked `[measured]`.
   Tefa at the end: *"looking down and then left right even better"*, *"all feels good"*, *"this feels right"*.
   `bodyplace.json` in the data folder overrides every number in play.
9. Tefa: *"you have no idea how much better the game already is, and this is just the prologue!"*

Rule 11 (per-frame work is native) is NOT met by items 7 and 8: they run in `visceral_re8_bridge.lua`, because the
calls they feed (`re8vr:update_body_ik`, `vrmod:set_standing_origin`, the stick at `set_AxisL`) are the loader's
script-side objects, which the plugin cannot reach. About 150 lines of Lua a frame; not measured for cost.

## 4. Sleeping controllers: `sleephands`

- Tefa: *"when the controllers go inactive, is there a way to just freeze hands in their current position? right now
  they teleport right to my face"*. Measured (recorder v9): a controller put down keeps reporting its spot for
  about 6 s, then reports exactly 0 0 0 until picked up; `is_using_controllers` stays true the whole time
  `[measured 2026-11-26, n=1, both controllers, Quest 3 through Virtual Desktop]`.
- The part: the bridge flags a controller at 0 0 0; while awake that arm's four joint rotations are remembered each
  frame, while asleep they are written. Tefa: *"idle hands now stay where they were"* `[verified-live, n=2 runs]`.
- The idle timer: `VR_MotionControlsInactivityTimer=86400` (was 30 on the bare base), Tefa: *"idle timer has to go,
  so there is no idle animations in the game, apart from the one used to carry rose"*. Not said seen or not seen
  since; the hands at the face were the sleeping controllers, not this timer.

## 5. For the doors (Tefa's words, nothing built)

- *"pushing doors open by hands, the only thing is walking with rose to the very first door, i cannot use my hands
  so the door must open with me just walking into it"*; again at the end: *"the door to bedroom where Rose crib is,
  has to open by me just walking into it"*.
- *"the door cannot have the normal 'open' sound, that plays when A is pressed or the door swings open just a tiny
  bit, it must only have the sound of the hinges, some creak, some gates have a metallic rusty sound, but we must
  mute the sound that is the first, door is now partly open sound"*.
- The reference: b178's `doors.cpp` + `visceral_re8_doors.lua`, note `2026-11-19-doors-open-at-the-hand.md` (the
  walk-in trigger `OnOverlapDoorPushCollider`, `StartInteractDoor`, the door states as murmur hashes, the leaf's
  colliders). An ordinary house door was never seen on that build.

## What is NOT established

- That any of it holds from a loaded save, past the prologue, with a weapon in the hand, crouched, on stairs, on a
  ladder, in a vehicle, or in a fight. Every run was a new game up to the crib and a few minutes after.
- What the still spine does to the hands: the two joints are written after the loader's arm solve, so the chest may
  sit up to about a centimetre off where the arms were solved from. Tefa noticed nothing; not measured.
- Steps near walls and furniture (the give-up never fired), and steps while Rose is carried.
- The cost of the bridge script's per-frame work.
- NOT done of this session's list: the carry check and the scene list are still `visceral_re8_game_arms.lua`; no
  build of the new series is in the builds store (the work is in git, commit e7e2b80 and the next one); the
  recorder (`visceral_re8_carry_rec.lua`, v10, dev only) is still installed.

## Tools

- `tools/close-game.ps1`: Village closed by its own window close, waits for the process to leave (Tefa, in /ms:
  *"from now on please close the game yourself when you need it closed, i'll still start it"*). Used three times.
- Live tuning without a restart: `bodyturn.txt` and `bodyplace.json` in the data folder, read every 2 to 3 s.
  Worth copying for every part that has a feel number.
