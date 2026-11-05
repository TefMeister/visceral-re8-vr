# The scope went through two tone curves, and its camera was still adapting (2026-11-05 23:30 - 2026-11-06 00:50)

Home PC, Fable, Tefa in the headset the whole time; every change made live through the scope's command file, the key
file and the settings the scripts poll, no restart until the measuring round. Tefa's ask: *"why some things are almost
neon bright and most of the world and scope are ok"*: balls of yarn, yellow paint, well pulleys, snow dust.

## What was found, in order

1. **The scope camera was adapting its exposure per scene while the world's was held.** Since 10-29 the steady-light
   script holds the MAIN camera (AutoExposure Disable + EV 6.4) and only the main (`sdk.get_primary_camera()`); the
   scope's clone camera kept `CLONE_AE_DEFAULT = 0` (Enable, from 10-02) plus EV = main + 3. Proof from the frozen frames
   (numpad +, `flicker-spike-N-src.ppm`): indoor yarn and outdoor snow came out at the SAME raw brightness (about 0.04),
   which only an adapting camera gives `[measured 2026-11-05, n=6 frames]`. Fixed live with `clonetm ae 2`; Tefa then
   brought the knob down from 10846 to 244 by eye, and the yellow text matched the world for the first time.
2. **A blink: one bright frame in ten** when the clone's EV was pinned at 9.4 while `clonelook` copied 6.4 from the main
   every 10 LockScenes (the 09-27 flicker, same cause). Fixed by making both say the same (EV = main, no offset) and
   stepping the knob down 9 notches (x1.25 each) to compensate.
3. **The clone's glow ran algorithm 0 while the world ran 2** (`clonediff SoftBloom`: `getAlgorithm` / `StandardV3` are
   not set_ pairs, so the copy never carried them). Copied live; Tefa saw no change from it, kept anyway for fidelity.
   Everything else (`Fog`, `VolumetricFog(+Control)`, `SSAOControl`, `GodRay`, `GeometryAOControl`, `SSRControl`) read
   equal between the two cameras. The clone has 21 of the main's 42 parts: it lacks every `app.*Controller`, which is
   expected (those write the via.render parts the clone already mirrors).
4. **The warm push (`wb_amount` -1.5) and the colour trim were not the cause**: with both neutral the red shrine window
   still glowed deep red in the glass. Measured in Tefa's headset screenshot (same curtain in the glass and in the
   world): green-to-red 0.39 in the glass against 0.52 in the world, blue equal `[measured 2026-11-06, n=1]`.
5. **The real one: two tone curves.** The frozen frame's finished picture (`-now.ppm`, our compositor's output) was almost
   black at the red window (R 15 of 255) while the glass in the headset showed it bright. The glass is the rifle's own
   lens material with our texture on it, `Reticle_Emissive = 1.0`, drawn inside the world and tone-mapped by the game
   like any surface. So the world got one curve and the glass got ours and then the game's. Tefa's by-eye knob had landed
   at 195 = a gain of 0.92, within 8 % of "no curve of ours at all", which is what that model predicts. With our curve
   made straight below the bright end (the held Contrast 1.0: the GT toe is identity below 0.22 and the linear section
   then has slope 1 up to 0.53), the lava-orange sunlit snow and the red window fell into place. **Tefa: "looks nearly
   perfect now ... maybe a few % warmer, it's so good I'm not even sure."** `[verified-live 2026-11-06, headset, n=1]`

## What is installed now (build b069, "Scope match")

- `re8_scope_cam_fix.lua` (edited in place, backup `scope-dumps/re8_scope_cam_fix-before-2026-11-06.lua`):
  `CLONE_AE_DEFAULT = 2`, `VR_CLONE_EV_OFFSET = 0.0`, `VR_CLONE_BLOOM_OFF = false`, and `vr_look_apply` copies the
  main's SoftBloom Enabled / algorithm / StandardV3 onto the clone.
- `re_scope_vr_settings.txt`: `exposure_gt 195.4`, `wb_amount 0`, `tone_wp 1`, `tone_mode 1`, `atmo_on 0`.
- `re_scope_trim.txt`: r 1 g 1 b 1 c 1. `whitepoint.json`: contrast 1.0 (the world ignores it; the scope copies it).
- `mir_cx` 0.51 (a stray numpad 6; one numpad 4 puts it back; not done).

## The instrument

- `dev-archive/native/tools/scope_dump_read.py`: reads the numpad + frames (undoes the x/(1+x) store), prints the raw
  light and the finished picture at the glass centre, re-runs the recipe with changes (`render`). ⚠️ The frames are
  numbered per game start (2001..2006, six per start) and OVERWRITE the last start's: copy them out at once. Run 2's are
  in `D:/RE Village REFramework builds/scope-dumps/run2-2026-11-06-0034/`; run 1 survives only as PNG previews.
- Tefa's Virtual Desktop screenshots are the world picture: in the headset the desktop window does not draw, but the VD
  screenshot shows the glass AND the world in one frame, so the same object can be measured in both. Five pairs
  (frame + screenshot: red window, pulley, yellow text, sunlit snow, wall) are in `scope-dumps/shots/`, unmeasured.

## Next (`MODEL: FABLE`)

1. The plugin: hand the glass raw light with a linear gain only (no GT curve, no exponential, no wb), into a float
   render target (the 8-bit one would band at raw 0.007), and let the game's curve do the rest. One knob stays: the gain,
   expected near 1.0. Then the few-percent warmth Tefa suspects can be measured on the five pairs and set once.
2. Measure the five pairs (glass vs world per object) with the reader, before and after the plugin change.
3. Decide whether the clone's bloom/fog matter at all now that the game tone-maps the glass (they are pre-tonemap, so yes
   for glow; keep the copy).
