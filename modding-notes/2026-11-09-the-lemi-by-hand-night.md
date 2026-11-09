# The LEMI by hand, the night of 2026-11-08 / 09 (home PC, Opus, Tefa in the headset)

Tefa at the end: *"it's really really good now with Lemi"*. Builds b088-b094, plus Window View 1.10 and the four helper apps.

## Found and fixed

- **The slide hand landing 20-33 cm off the gun** after a pause (b087). Hand smoothing was suspected and ruled out
  (`[disproved 2026-11-08, n=1]`: still off with the left hand raw). b088 added a "who moved it" line to every grab:
  the IK reached its target exactly and the right hand sat on its own; OUR target was 35 cm from the drawn slide (11-14 cm
  on good grabs). Cause: `rack.cpp` read the slide's place in the gun hand at LateUpdateBehavior, before the arms are
  solved, where the gun still sits in the animation's pose, about 20 cm away after the controllers have slept (Tefa's
  lead: "it's related to controllers going inactive"). b089 reads it where the gun is drawn (BeginRendering).
  `[verified-live 2026-11-09, n=3]`: after a controller sleep the early reading was 18-21 cm off and every palm still
  landed 6-10 cm from the slide, as on good grabs.
- **Fingers opening at the end of the rack**: the Hand Poser window and the game script loaded an EMPTY "at the back"
  pose file and let the fingers go; then the hand came off inside the slide's zone and `fingers.cpp` opened it. An empty
  pose now counts as none (both), no opening after letting go of a part until the hand leaves the grab areas, and a
  pistol slide keeps its pull spot to the end (bolts and pumps keep their stage) (b093, b094).
- **The way back to the controller teleported**: the 0.40 s ease was overwritten by every later solve of the frame
  putting the free hand back on the controller; later solves now draw the eased place (b093); 0.25 s (b094).
- **The gun hand loosened 3-5 s after a shot**: the right fingers are read 0.12 s after a live shot and held per gun
  (righthand.cpp Firm, b094).
- **The right hand relaxed when the left took the magazine**: a spot's pose file holds only the left hand and replaced
  the gun's own pose (both hands). A spot's pose now sets only its own hand (Hand Poser f552025).
- **Sleeping controllers threw the hands in front of the face**: a controller whose pose has not changed by one bit for
  20 frames lowers its hand beside the hip (sleephands.cpp, b090); Hand Freeze and Window View's CONTROL mode are read
  from their shared blocks so a frozen hand is never "asleep" (b092; Tefa: "hand freeze works!").

## Built for the helpers

Window View 1.10 shares the right stick's left/right and makes A a left click; Hand Poser, Grip Zones, Gun Poser and
Animation & Timing step ticked sliders with the right stick (left/right 1, up/down 5, held repeats), Y = undo, B = redo,
X = untick all. Hand Poser: the thumb tip's curl moved to the right-hand column (it curls on Y), the dock box's
BACK/FORWARD no longer cut.

## Left for next time (board rows)

The hand turned around a magazine taken out; the left forearm twisting with the wrist (forearm.cpp holds it, which is
why the wrist bends like a pretzel); fingers flicking with a magazine out; the step onto the slide (Tefa's video); the
right-side release pushing forward; ammo counters at zero until a shot; the free left hand's jitter (Fable); the live
connector (praydog's needs .NET, which this REFramework build lacks; Wednesday).

## b095 (2026-11-09 10:38, home PC, Opus): the left forearm twists with the hand `[compile-verified]`

Tefa (02:3x): *"left wrist really needs to turn with the forearm, right now forearm is frozen so it doesn't rotate at all
and that's why my wrist in game is whanged into a prezel, but that is the only way to get the hand to grip around the handle
nicely"*.

- `forearm.cpp` still takes the twist joints' pose 45 frames after a draw (b094's grip), but that pose is now the ZERO of a
  twist, not a freeze. Once a frame, after the arm solves (BeginRendering), it reads L_Hand's local turn under L_Forearm
  and takes its twist about the forearm's long axis (the axis = L_Hand's local position, the bone direction).
- The twist since the gun settled is unwrapped (always the nearest way round, so the half-turn flip that made the rifle's
  forearm jump 100 deg in one frame on 2026-11-01 cannot happen), capped at 150 deg, and moves at most 20 deg a frame.
- Each twist joint turns by that twist times its place along the forearm (0 at the elbow, 1 at the wrist), worked out at
  the settle from the joints' own positions; whether a twist joint hangs from L_Forearm or from another twist joint is
  read at the settle too, and logged ("forearm: twist follows the hand: axis ..., shares ..., parents ...").
- The hand itself is not touched, so the grip around the handle stays as it was.
- Switches in `settings.h`: FOREARM_TWIST_FOLLOW_ON (false = the 2026-11-01 plain hold), FOREARM_TWIST_SHARE,
  FOREARM_TWIST_MAX_DEG, FOREARM_TWIST_RATE_DEG.
- Not run yet. What to look for in the headset: the sleeve turning with the hand palm up / palm down; the rifle's bolt and
  hand-back not jumping; the log lines above.

**Worn 2026-11-09 ~11:0x (Tefa, headset): "yes it works really well now"** `[verified-live 2026-11-09, headset, n=1]`.

## b096 (2026-11-09 11:11, home PC, Opus): the slide stays locked back; handgun magazines move along the grip `[compile-verified]`

**Slide.** Tefa: *"when i take out a half full mag, shoot the one bullet that is left in the chamber, and then put the same mag
in, then the slide closes as soon as the mag is in"*. Read in the code: the mod never draws a locked-back slide itself; the game
holds an EMPTY gun's slide back, and the moment `fill_magazine` makes the gun "loaded" again the game lets it go, although
`rack::need("a magazine into an empty gun")` has the trigger waiting. Now (`rack.cpp`, SLIDE_LOCK_HOLD_ON): while the gun is
empty and nobody holds the slide, how far back the game holds it is kept per gun (at least SLIDE_LOCK_MIN of SLIDE_BACK_M;
log "empty, the game holds the slide N% back"); with the rack due the slide is written there until the hand racks it
(taking it there counts as already pulled: "it only has to go home"). A hold-closed left from an earlier rack is dropped while
the gun is empty, so it cannot shut an empty slide.

**Magazine.** Tefa (01:1x): *"make handgun magazines move only up and down in the grip shaft until taken out"*. New state
`RAIL` (`reload.cpp`, THE GRIP'S RAIL; MAG_RAIL_ON): after B with the hand on it, the magazine sits on the grip's line (seat ->
RELOAD_MAG_DROP_M below, the line the B drop already used), as far down as the left controller has moved along that line,
measured in the right hand target's frame (the gun's own transform lags); the drawn hand stays on it. Past the bottom = in the
hand; pushed back to within MAG_RAIL_SEAT_U of the top after moving MAG_RAIL_MOVED = seated (no LT needed); LG let go = slides
out and falls. The same magazine at the well with LT held now goes on at the bottom of the line and is pushed up the same way
(instead of the 30 % push). Not yet worn; the likely rough edge: a small jump of the hand and magazine where it leaves the bottom.

**b096 worn 2026-11-09 11:27 (Tefa):** the slide now stays back after the magazine goes in (log "the game holds the slide 67% back") and the magazine rail works ("otherwise seems to be working better again") `[verified-live 2026-11-09, headset, n=1]`; but taking the slide snapped it shut. Log: the take had no "N% back when taken" line, so the hand started from closed: our own hand-on write had already shut the joint before the take read it. **b097** (compiled, not installed while the game runs): a slide held locked back starts the hand at the held travel.

**b097 worn 2026-11-09 ~11:45 (Tefa): "yep that is working too now!"** `[verified-live 2026-11-09, headset, n=1]`.

## b098 (2026-11-09 11:5x, compiled, not installed while the game runs): the first grab after a launch

Tefa (two screenshots, 11:46): *"when i launch the game and first grab the Lemi grip, my hand is away like in one of the
screenshots, then when i do LG+B eject and put the mag back in, it's fine, also fine after swapping weapons"*. Log: the first
two grabs docked the palm at forward +2.4 cm, yaw 19 deg (dockreport), every grab after the first eject at -2.3 cm, yaw 0.
Cause: the magazine's seat (`g_rest_pos` / `g_rest_rot`) was read only when a magazine came out (begin_drop / pull_out); before
that the hand docked on a blank default seat. Now `read_rest` reads it from the seated magazine 0.5 s after every gun comes
out (or at once if the hand takes it first); log "magazine seat read". Switch MAG_SEAT_READ_ON. Also from the same log: the
hand turns about 125 deg in one frame when it docks onto the magazine; the forearm follows at 20 deg a frame (b095's limit).
