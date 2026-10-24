# 2026-10-24 (night, /pd, Fable): the body turns like RE2's (idea 6), built unseen

`/pd` on the home PC. **The game was not launched; nothing here has been run.** Installed (dll with `body.cpp`),
backup `/d/RE Village REFramework builds/_backup-2026-10-24-20xx-before-visceral-re8-deploy`.

## What RE2 does (read in REFramework's source, `src/mods/FirstPerson.cpp`)

`FirstPerson::update_player_body_rotation`: every frame the player's yaw is turned toward the camera's yaw by a step that
grows with the angle between them (`angle / 720 * dt * BodyRotateSpeed`, default 0.3), so the body lags the look and
catches up smoothly; looking around with the headset does not move it, because the camera it follows is the game's
stick-driven camera `[inferred-static 2026-10-24]`. RE2 is a third-person game, so the body also faces where it walks.
That is the feel Tefa wants in Village.

## What Village does

- Neither praydog's VR (`re8_vr.lua`, REFramework's `RE8VR.cpp`) nor Andyalpa's pack turns the body: praydog applies the
  headset to the camera and the hands, Andyalpa only reads the body's facing (`HJ.torso_yaw_axes`: the root / Hip joint's
  yaw) to place his holster zones `[inferred-static 2026-10-24, read]`.
- The game's own first-person code decides the player transform's yaw; the camera and the aim hang off it, so turning the
  transform would turn the view (praydog's warning: "so the camera doesn't spin uncontrollably").
- The game has its own body-direction machinery, most likely for its third-person mode: `calculateBodyDirection`,
  `get_/set_bodyDirectionTarget`, `BodyRotateSpeedBase`, `getCameraYaw`, `cameraYawSpeed`, `get_isTPSMode`,
  `set_turnAngle` (names in `re8.exe` `[measured 2026-10-24, strings]`; which types own them is not known: the
  executable stores type names apart from method names). `body::probe_types` finds them on the first frame (every
  app.*Player*/Character*/Camera* type asked for those methods) and appends the owners to `type_probe.txt`.

## The lever: turn only what is drawn

`src/body.cpp`: after the animation has posed the skeleton (LateUpdateBehavior post), every joint of the player is turned
about the vertical axis through the transform's position by an offset theta; the transform itself (view, aim, walk) is
untouched. Theta lags a target with RE2's rule (rate = `BODY_TURN_GAIN` x remaining angle, floor `BODY_TURN_MIN_DEG_S`):

| state | target for the drawn body |
| --- | --- |
| aiming (the aim flag, or the right grip held) | the look direction |
| walking (transform moving faster than `BODY_WALK_MIN_MPS`) | the direction of travel; back-pedalling (travel more than `BODY_BACKPEDAL_DEG` from the look) keeps the look |
| standing | nothing, until the head is more than `BODY_HEAD_SLACK_DEG` from the body; then the body comes round to the slack's edge |

The look direction is the headset's rotation carried into the world (the camera's world rotation), forward +Z as
praydog's camera code uses. Praydog's hand IK targets are separate transforms written at PrepareRendering, and the arm
IK solves after our write, so the hands should stay on the controllers `[hypothesis]`.

**Which step runs last:** the animation decides the joints at UpdateMotion; this writes at LateUpdateBehavior post
(after it, before the IK and the render); the gun joints needed a second write at PrepareRendering because the engine
rewrote them there. So the lever measures itself: at PrepareRendering post the root joint is read back and counted as
`held` or `undone`; the once-a-second log line carries both counts, the mode, the look / transform / drawn / target
yaws and the speed:

    [visceral-re8] body: mode walk, look 123, transform 120, drawn +18 (target +25), speed 1.40 m/s, render check: held 60 undone 0

## What is NOT established, and what would show the derivation is wrong

- `undone` climbing: the engine rewrites the joints after LateUpdate; move the write to PrepareRendering post and skip the
  arm chain (the IK would have run already).
- `look` and `transform` 180 degrees apart while looking straight ahead after a recenter: the forward convention of one
  of them is -Z, not +Z; flip `fwd_yaw`.
- the hands leaving the controllers while the body is turned: the IK ran before our write; write earlier (UpdateMotion
  post) or skip the arm joints.
- the body stays while walking sideways in the headset but the log says `drawn` is moving: the write is held but the mesh
  is drawn from somewhere else (a motion bank re-pose at render); then the game's own `set_bodyDirectionTarget` route
  is the next try, with the owner type from `type_probe.txt`.
- the body turning the VIEW: the transform was turned, which this never does; if the camera follows the root joint rather
  than the transform, exclude the camera's joint.
`[compile-verified 2026-10-24]` only.
