# 2026-10-29 (afternoon) — the zone spheres were drawn too SMALL, not ignoring their size (home PC, Fable, flat desk runs)

## The job
Tefa picked it ("all are important, so 1 please for now"): the board row *"THE DRAWN SPHERES IGNORE THEIR SIZE"* (10-25
23:20: the start sphere did not grow or shrink, the beads of the dotted line not seen; six tries on the spheres before that).

## What was wrong
`visceral_re8_zones.lua` needs the sphere MODEL's half size to turn a zone's radius into a scale. The model's own box
(`get_ModelLocalAABB`) read nil at spawn, the mesh still loading, so the script measured the WORLD box after the zone's
scale had been set and divided by that scale. The world box lags the transform, so the "model size" came out different
every run: 0.104 m on 10-25, 0.030 m this morning, and with the test guess of 0.5 m this afternoon a sphere drew at 0.8 cm.
With 0.104 every sphere drew 3.5x too small (a 14 cm zone as a 4 cm ball) and the 8 mm beads at 2 mm: invisible. That is
the 10-25 sighting.

## The ruler `[measured 2026-10-29, n=1]`
Camera from the RE Engine MCP (position, FOV 51.3 deg), the sphere's position and scale from the log, a screenshot of the
1920 x 1421 window: the ball 0.466 m from the camera drew with a 530 px radius, which is 0.157 m, so the model's half is
0.033 m at scale 1. Its own box says 0.030 m. The box is right; the drawn size follows the number. Method and scripts:
`dev-archive/recon/2026-10-29-sphere-ruler/`.

## What changed (installed, flat-tested)
- The model's own box is asked every frame until it answers (frame 1 after the spawn in practice), the world-box measure is
  gone, the fallback is the test ball's known 0.030 m. Log: `sphere model's own box read on frame 1: half size 0.0300 m`.
- A PROOF line one second after a sphere is scaled: `sphere 2 PROOF: asked r 0.141 m (scale 4.700), drawn world half
  0.141 m` (the world box one second later agrees with the number).
- The pair beads are back on (`PAIR_DOTS_SHOWN = true`).
- The "Sphere model size fix" slider in the menu still overrides everything if a run ever looks wrong.

## Worth knowing for the headset
A 14 cm zone IS a 28 cm ball, pistol-length; on the flat screen 47 cm from the camera it filled a quarter of the view. If
the spheres look too big in the headset now, the ZONE radii are what to shrink, not the drawing.

## Driving facts (flat)
Through Steam, `re8drive.py boot` stops at the "load most recent?" question (hidden behind the Emporium window): Up, F,
wait 55 s, F (the chapter card), Insert (the overlay). The pistol is in hand at the save, so the spheres spawn. A Lua edit
needs a relaunch (no live reload from the desk); about four minutes a round.
