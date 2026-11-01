# The grip-zone spheres: only the first ball ever drew (2026-11-01, Opus, OpenXR Simulator, no headset)

Tefa: "can you use the mcp bridge and openxr simulator to find all the activation spots on Village weapons and get the
spheres sorted out, so they all show in VR". Before: the M1897's pump and shell port, and the pistol slide, never showed;
the magazine and front grip did.

## Found `[verified-live 2026-11-01, simulator, n=4 guns]`
- The zones script made one ball per zone (eight), all at once when a Grip Zones row opened. **Only the first one made drew.**
  Proof: on the LEMI the magazine ball (made first) drew at the hand; the well ball, made next and placed 10 cm from it,
  drew nothing; the slide, pump and shell-port balls never did. Positions were right all along (the WHERE lines: asked =
  really, 0.000 m off; the pump 0.54 m up the shotgun from the gun hand, which is where an M1897's pump is).
- Two guesses ruled out on the way, both reverted: the rack publishing its sphere too early in the frame (moved to the draw
  step: no change), and the pump joint's world reading being stale (worked out from the gun's own transform and the local
  poses up its parents instead: 0.0 cm apart, so not stale).
- Why the later balls do not draw is not known `[hypothesis: something per created mesh, set once]`; not needed any more.

## The fix (visceral_re8_zones.lua, build b028)
ONE ball, moved and sized to whichever row is open (only one row is open at a time). It also makes one mesh instead of
eight: the setMesh crashes of 10-25 / 10-30 / 10-31 came from making these balls.

Drawn, checked by screenshot in the simulator: M1897 pump, shell port; LEMI magazine, well, slide (right), slide (left);
F2 rifle bolt, magazine, well, front grip; W870 pump, shell port.

## Driving Village on the simulator (also in the game's KNOWN.md)
Runs on Single Frame Multipass only (Two Frame Sequential freezes on the first frame). VR Bench gives the A button and the
sticks; number keys 1-4 take out the quick-slot guns (here 1 W870, 2 LEMI, 3 M1897, 4 F2); the game pauses whenever its
window is not in front.
