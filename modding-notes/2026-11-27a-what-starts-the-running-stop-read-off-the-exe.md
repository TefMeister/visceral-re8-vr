# What starts the running-stop motion, read off the exe (2026-11-27, /pd, Fable, RE8-096)

**The game was not launched. Nothing here has been run in the game.** Everything is read from `re8.exe` on disk
(the type database through the toolkit's `tdb-read.py`, the code through the scripts in
`dev-archive/recon/2026-11-27-runend-static/`). The lever at the end is built, syntax-checked and installed switched
OFF; it has not been worn.

Asked by Tefa the night before: *"can we just eliminate these animations as we did with re2"*; the hands *"jank back a
little ... more teleporty than not ... and then sort of smooth out"*.

## 1. What is established

- **The stop is two states of the body's motion machine, `RunEndL` and `RunEndR`** (`app.PlayerDefine.StateName`), and
  one action id, `BaseActionID.RunEnd` (hash 3705329191). `[inferred-static 2026-11-27]`
- **`app.PlayerMovement.processRunEnd` is at 0x1411d51d0 and only LISTENS.** It adds the two state hashes to its
  parameter's hash set and hangs three handlers on it: `<processRunEnd>b__348_0` as LateEnter, `b__348_1` as Run
  (every frame while the state is on), `b__348_2` as LateExit (parameter offsets 0x68, 0x40, 0x90 = the fields
  LateEnter, Run, LateExit of `app.MotionDelegate.ParameterBase` plus the 0x10 object header).
  `[inferred-static 2026-11-27, the three method numbers 0x22ac5..7 read from the exe's method-slot table]`
- **Nothing in the game's script asks for the stop by name.** The hashes of `RunEndL` / `RunEndR` are made once (the
  static constructor at 0x142b0af90 stores them at 0x14c4df2d8 / 0x14c4df2dc) and are read by exactly four functions
  in all of the code: the four `processRunEnd` copies (Ethan 0x1411d51d0; the three other playable characters
  0x141606410, 0x142e43640, 0x143034920). The strings themselves are loaded nowhere else.
  `[inferred-static 2026-11-27, every rip-relative reference in .text searched]`
  So the step "run -> stop" is taken by the motion machine itself (its data file in the pak) or through the action id,
  from what the movement object holds at that moment; it is not a call we could hook by the state's name.
- **No script condition decides it either.** Of all types that derive from `via.behaviortree.Condition`, the only
  player one is `app.CheckPlayerIdCondition`. `[inferred-static 2026-11-27]`
- **The arms have a stop state of their own, per weapon kind:** `Gun.ReadyRunEnd`, `Melee.ReadyRunEnd`,
  `Item.ReadyRunEnd` (and `JogEndOnRArmDM`), with their own routines `app.PlayerGun.processReadyRunEnd` (0x1411d1b40
  for Ethan, one handler) and `app.PlayerMelee.processReadyRunEnd` (three handlers). They sit beside
  `ReadyIdle` / `ReadyMove`, the states that hold the weapon arm while standing and walking.
  `[inferred-static 2026-11-27]`

## 2. Why only the right hand slips `[hypothesis, from section 1]`

At a running stop two things change on the same picture: the body goes to `RunEndL/R`, and the weapon layer goes from
`<Weapon>.ReadyMove` to `<Weapon>.ReadyRunEnd`. The weapon layer drives the arm that holds the weapon: the right one.
The left arm has no state of its own there and only follows the body, which the hand solve already absorbs (0.1 cm
measured). The right arm gets a new pose from a second source on that picture, and the hand solve is one step behind
it: the 2.5 to 3 cm slip. Not proven: it needs the stop seen once with the knife (a different routine, three
handlers) and once with empty hands; if the slip changes with what is held, this is it.

## 3. What is NOT established

- **Which number or flag makes the motion machine take the step.** The candidates on the movement object are
  `IsJog` (+0x190), `IsJogging` (+0x191), `JogRate` (+0x130), `IsSprint`, `SprintRate`, `fromSprint` (+0x348);
  `JogEndThreshold` was tried in the headset and is not it (note 2026-11-26f section 8d). The code that reads them
  could not be named: see the next point.
- **The exe's type database carries no code addresses.** All 880,234 method records have an empty function field on
  disk; virtual methods can be found through the type's virtual table, a lambda cannot. Functions are laid out
  sorted by method name inside groups of classes, but the groups could not be pinned down, so the three handlers
  `b__348_0..2` and the move handlers `<processMove>b__345_0..2` were NOT read. This is the wall; in the running
  game REFramework has every address, so a hook by name works there.
- Whether the body's 3 cm pop is the stop motion's first frame or the camera type change that comes with it
  (dossier §12): both happen on the same picture.

## 4. The ONE lever: "stop jog" (`bodyplace.json` `"stopjog": 1`), installed OFF, not worn

RE2's fix was to put the game's jog mode down at the moment of the stop. The same idea here, by field:

- The left stick is handed to the game in `B.turned_stick` (called from `re8_vr.lua` right before `set_AxisL`),
  which is BEFORE the game's own update of that frame.
- On every frame the handed stick is shorter than 0.30, `IsJog`, `IsJogging` are set false and `JogRate` 0.0 on the
  movement object (kept from the one `processMove` call). While the stick is pushed nothing is touched.
- If the step is taken from any of the three, the game finds a player who was not jogging and goes run -> idle with
  its own blend; the weapon layer's stop state follows the same choice.

It proves or disproves itself in `re2_framework_log.txt`:

| line | meaning |
| --- | --- |
| `stop jog: stop N, before the write IsJog .. IsJogging .. JogRate ..` | one per stop with the lever ON: what the three held when the stick was let go |
| `stop jog: the game ENTERED the stop motion (N), K frame(s) after the stick was let go, lever ON/off` | a counting hook on `<processRunEnd>b__348_0`; printed with the lever off too, so the first stops give the baseline K |

| outcome | reading |
| --- | --- |
| lever ON, no ENTERED lines, Tefa sees no pull-back | done: this is the switch |
| lever ON, ENTERED still printed, the three were true/non-zero before the write | the step is taken earlier than our write or from something else (speed, the foot's sequence track); next: the three handlers hooked by name, the state left from `b__348_0` |
| lever ON, ENTERED still printed, the three were already false / 0 | these fields are not it; same next step |
| no ENTERED lines even with the lever OFF | the hook is on the wrong handler (the name differs in the running game); the log's "counting hook ... FAILED" line says so at start |

A diagnostic that would show the DERIVATION wrong rather than the lever: ENTERED printed with K = 0 or 1 with the
lever off. Then the game takes the step inside the very update that first sees the released stick, and only a write
before that update can work; K of 5 or more means it waits (for the foot, or for the speed to fall) and a later,
simpler write would do.

## 5. Installed now (game closed)

Everything of note 2026-11-26f section 8e, plus the bridge of this commit (the lever, OFF: `bodyplace.json` is
unchanged and has no `stopjog`). The bridge it replaced is kept in the rebuild-2 backups folder,
`2026-11-27-before-stopjog/`; it was byte-identical to commit 75548a6's. The install stamp was three files behind
(plugin, bridge, `re8_vr.lua` changed during the night's /ms run) and is re-recorded.

## 6. For the tools

- `tdb-read.py` prints `@-` for every method of Village: the function field is empty on disk. Worth a line in its
  help text, and a `slots` command (the exe's table of 11,042 method slots at file offset 0x8684ce0: slot address,
  method number) plus the string-literal cross-reference (`litx.py` here). Tool idea, not done tonight.

## 7. Worn the same night (/ms, 01:10 to 01:45, Tefa in the headset, the LEMI and the knife)

- **Run 1, lever off, with a counting hook on `<processRunEnd>b__348_0`:** the hook fired 445 times in nine minutes,
  in pairs, about half a second apart while running, with the stick held. So `RunEndL` / `RunEndR` are marks inside
  the run ("which foot is forward"), not the start of the stop motion. **Section 1's reading of them as the stop's
  states was wrong** `[disproved 2026-11-27, n=445 calls, one run]`; "nothing asks for them by name" still holds.
  The hook is out.
- **Run 2, lever on with IsJog / IsJogging / JogRate put down:** Tefa: *"pull-back is the same"* (later: *"might be
  smaller, but it is very hard to tell"*). The log: `IsJog` and `IsJogging` are false at every stop; what is up is
  `SprintRate` (0.94 to 1.0), sometimes `IsSprint` and `JogRate` (up to 0.7) `[measured, n=9 stops]`.
- **Run 3, lever also puts `IsSprint`, `IsKeepSprint` false and `SprintRate` 0.0:** Tefa: *"pullback is gone"*
  `[verified-live 2026-11-27, n=1 run, 9 stops]`. INSTALLED, `bodyplace.json` `"stopjog": 1`. So the stop motion is
  chosen from the sprint level the movement object holds on the frame the stick is let go.
- **A new fault, not from the lever (there with the lever off and with the hook out):** Tefa: *"when holding out Lemi
  and running, hand is shaking with the pistol like it hasn't before"*; *"like a real weapon would shake in hand
  when running ... an irregular wobble, or a bobbing but not just up and down"*; walking too; the knife too;
  *"sometimes more sometimes less"*. Measured: the wrists stay on the controllers while moving (gap steady at 8.07 cm,
  0.04 cm a picture, the same as standing; walk file, 6,619 pictures) and the weapon does not move against the right
  hand at all (0.00 cm, under 0.1 degree, sampled after LockScene; probe `archive/probes/visceral_re8_weapon_probe.lua`,
  23 moving seconds) `[measured 2026-11-27, one run each]`. Tefa saw it, so the measurements are looking in the wrong
  place: both compare hand, weapon and controller with each other, none compares them with the VIEW at the moment
  the picture is drawn. Suspects, not tested: the origin being moved after the hands are placed (the body's place
  follow, the camera glide, the room step); a stale drawn matrix. The body hold (`lean`) switched off live: no answer
  from Tefa on that run. Board row RE8-101.
- **Seen in passing:** the gate whose chain is cut with the bolt cutters did not open at a hand push right after the
  cut; once it had closed again it did. Board row RE8-102.
