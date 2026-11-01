# Driving Village on the OpenXR Simulator (no headset)

Small tools from 2026-11-01. They need the VR Bench layer on for re8.exe (`vrbench.py start <re8.exe>`), the OpenXR Simulator,
and Village on Single Frame Multipass (Two Frame Sequential freezes on the first frame).

- `drive.sh`: launch on the simulator and drive to gameplay (A, A, left stick up, A, wait, A). Writes `pid.txt`.
- `keys.py <pid> [keys]`: bring the game forward (it pauses when not in front) and tap keys; 1-4 take out quick-slot guns.
- `vb.py press <hand> <button> [sec]`, `stick.py <hand> <x> <y>`: VR Bench buttons and sticks.
- `hands.py rx ry rz ryaw rpitch [lx ly lz lyaw lpitch]`: hold both controllers still (room metres, degrees).
- `walk.py <zone>`: walk the left controller to a grip zone by the game's own hand_cm (zones_state.json);
  `walk.py squeeze|trigger <0|1>` keeps the pose and presses.
- `stroke.py <m> [steps] [hold]`: pull the left controller back along the gun and home (a rack / pump).
- `stroke2.py <m> [steps] [hold]`: the same for either hand (`STROKE_HAND=right`), along the line between the hands
  (`STROKE_DIR=hands`) or a given muzzle direction in room (`STROKE_VEC=x,y,z`). The controller's own forward is NOT
  the barrel: a pull along it counted a quarter of its length on the F2.
- `walk.py rsqueeze <0|1>`: RG.
- `openrow.py`: keep a Grip Zones row open (the key in `openkey.txt`; `stop` ends it).
- `wins.py <pid> [class]`: list the game's windows; with `via` it closes the game cleanly.
- `waitchain.py <pid>`: what each thread of a hung program waits on (Windows Wait Chain Traversal).
