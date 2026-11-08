# 2026-11-08: which way every helper-app slider moves the hand, measured

Tefa (headset test of b086): *"go over all the sliders and how they move hands. left side must always be down, inwards, rotate
left, bend left and so on, right must always be up, outwards, rotate right ... some of the sliders read left and right on them,
but actually move the hand the opposite way. also thumb sliders might be mixed up a little."*

## How it was measured
`tools/sim/zz_test_axes.lua` (TEST ONLY, taken out after) on the OpenXR Simulator: at one BeginRendering it turns every hand
joint +10 degrees on each local Euler axis (`set_LocalEulerAngle`, the call Hand Poser's script uses), reads the world turn, puts
the joint back, and writes `axes_out.json`; it also writes the held gun's Transform axes. `tools/sim/axes_hand.py` reads it in
the hand's own frame (bone, palm, knuckle line). Log kept: `D:/claude video game stuff/re8-logs/2026-11-08_2215_sim-axes.txt`.

## What it found `[verified-numerically 2026-11-08, simulator, n=1 pose per hand]`
- Fingers, thumb and wrist: +X twists, +Y swings sideways, +Z bends. Left hand: +X turn right, +Y left, +Z OUT (wrist: up).
  Right hand: +X turn left, +Y left, +Z IN (wrist: down). The hands are mirror images, so the old IN/OUT words were right on
  the left hand and backwards on the right.
- The right hand's middle / ring / pinky, curled round the grip, mix X and Y (Euler angles do that past a big bend); the table
  uses the straight-finger reading.
- The gun's own axes (LEMI, F2): **+x points LEFT**, +y up, +z the muzzle. Everything laid out "in the gun's axes, x right"
  (zones.cpp, dockpose.cpp, the clips' whole-hand move, the slide hand) has had x backwards; +rx tilts DOWN, +ry turns LEFT,
  +rz rolls right.
- Gun Poser's aim is in the controller's axes (OpenXR, x right, z back): +yaw turns LEFT, +roll rolls LEFT; pitch, x, y, z fine.
- The thumb: L_Thumb1 3.2 cm from the wrist, Thumb1 to Thumb2 4.9 cm, Thumb2 to Thumb3 3.3 cm: base, big knuckle, tip joint,
  as the window names them, and Hand Poser's script finds them by name. Tefa's "TIP moves the middle" is not explained by the
  names; left for the next wear.

## What changed
The apps show the number turned round where + sat on the wrong end; every stored number keeps its meaning (poses, zones,
dock poses, clip edits untouched). Labels name the left end first. Hand Poser + Animation & Timing: `HandAxes.cs`; Hand Poser
`DockBox.cs`; Animation & Timing whole hand; Grip Zones / Gun Poser zone sliders (x) and Gun Poser yaw / roll.

## The slide-sphere click
Not a game sound in the headset log, and not heard on the simulator (`tools/sim/hear_entry.py`, about -45 dBFS throughout, with
and without LG). The one thing the mod fires at that moment is a 50 ms half-strength buzz on the left controller as it takes
the slide: switched off (`RACK_TAKE_BUZZ = false`, b087). **Ruled out the same evening** `[disproved]`: Tefa says the click
comes NOT every time and NOT while holding LG, just with the hand nearing the gun, and the take buzz only fires with LG. Parked by
Tefa ("let's leave it for now").
