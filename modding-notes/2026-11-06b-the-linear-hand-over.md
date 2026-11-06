# The linear hand-over: the scope plugin gives the glass raw light through one gain (2026-11-06 18:10 - 18:40)

Home PC, Fable, no game running. The follow-up to `2026-11-06-the-scope-went-through-two-curves.md`: last night's
finding was that the glass is the rifle's lens material (`Reticle_Emissive 1.0`), tone-mapped by the game AFTER the
scope plugin's pass, so the scope's picture went through two curves. Tefa's by-eye knob had landed within 8 % of "no
curve of ours", which that model predicts. Tonight the plugin does exactly that.

## What changed (scope plugin, staging branch `village-1.1.6-scope-trim`, DLL 739e7803)

- **`tone_mode 2`, the new default: the linear hand-over.** On the raw-HDR path the pixel shader multiplies the raw
  light by the exposure knob and nothing else: no white balance, no sky fill, no GT curve, no white point divisor. The
  knob is still `exposure_gt` (knob x 0.4 x 2^-EV, EV 6.4 held), so Tefa's 195.4 = a gain of 0.92 carries over
  unchanged; numpad 8/2 still step it. The game's own tone curve then maps the glass the same way it maps the world.
- **The scope image is float now** (`R16G16B16A16_FLOAT`, 480x360, and its held copy). The old target used the
  swapchain's format, fmt 28 = 8-bit linear, where raw 0.007 is under two steps of 255: bands in the dark glass. The
  blit into the 8-bit sRGB glass target (fmt 29) encodes once on the way in, as before. The backbuffer copy and the
  flat composite keep the swapchain's format (a copy needs it).
- Numpad 5 cycles LINEAR -> GT -> EXP -> EXP frozen -> LINEAR; the log names the mode (`tone_mode_name()`).
- The frozen-frame dump (numpad +) writes our float picture clamped 0..1, the way the glass gets it, so
  `scope_dump_read.py` reads `-now.ppm` unchanged; only a raw SOURCE is stored as x/(1+x). The reader learned
  `--curve linear` to preview the new recipe on last night's frames.
- Checked: all five shader entry points compile with fxc (`tools/check-shader.sh`); Release build with the VS 2022
  Build Tools; `[compile-verified 2026-11-06]`. Not run in the game yet.

## What is installed (visceral-re8-vr build b070 "Scope linear hand-over")

`reframework/plugins/re_scope_vr.dll` 739e7803 (the b069 one, 2ac1dd49, kept in `D:/RE Village REFramework builds/
scope-dll-backups/`); `re_scope_vr_settings.txt` `tone_mode=2`, the rest as b069 (`exposure_gt 195.4`, `wb_amount 0`,
`tone_wp 1`, trim 1/1/1). The Lua side is b069's (AE held, EV offset 0, bloom algorithm copied).

## The clip at the top

The glass target is 8-bit, so raw light x0.92 above 1.0 goes flat white in the glass while the world's own shoulder
still separates it. Under the old curve the shoulder began at 0.53 and the same clip sat at infinity, so the top end
is the one place the two recipes differ below the game's curve. How much of a frozen frame sits above 1.0 is measured
by the scratch script on last night's frames (result in the board row). If the sun on snow goes flat, the next step is
a float glass target (an authored fmt-26 .rtex like the clone's `scope_1920_1080_hdr.rtex`), which keeps the whole
range; the lens material would then see values above 1.0 and the game's curve would handle them like the world's.

## The warmth: not measurable from last night's pairs

The eight headset screenshots (`scope-dumps/shots/`) are from 00:12 to 00:37; the final recipe (curve straight,
trim off) went in at 00:40, so every pair shows the OLD scope curve (per-channel, contrast 1.6). Measured anyway
(`pairs.py`, same object in the glass and in the world, linear light): the red shrine window came out far redder in
the glass (green-to-red 0.30-0.43 of the world's), the stone wall slightly cooler and 1.7x brighter, the orange haze
bluer-poor: the signature of a per-channel contrast curve, not of a tint. `[measured 2026-11-06, pre-fix shots,
n=1 each]`. The few-percent warmth Tefa suspects in the FINAL picture needs a pair taken with b070: numpad + on the
stone wall filling the glass with the wall around it, and a Virtual Desktop screenshot in the same second. Then the
glass-to-world ratio on that grey wall is the trim, set once in `re_scope_trim.txt` (a per-channel gain in linear
light is a white balance now, since nothing of ours comes after it but the clamp).

## Next

1. Tefa's look at b070 (the scope on the same spots: the red window, the yellow text, the sunlit snow, the wall).
   `MODEL: OPUS` to read the result; FABLE only if the picture is wrong in a way the frames do not explain.
2. The wall pair (above) and the trim set once from it.
3. If the sun on snow goes flat white in the glass: the float glass target.
