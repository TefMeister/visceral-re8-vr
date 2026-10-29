# 2026-10-29 — the game's automatic brightness kept off (home PC, Fable, desk; not run yet)

Tefa: *"remove the adaptive lighting from RE8 and 3"*. RE2's switch of 2026-10-28 (`exposure.cpp`) is ported as it stood after
b192, brightness part only (no colour-grading or contrast change): every frame at BeginRendering the main camera's
`via.render.ToneMapping` gets AutoExposure = Disable and its AutoExposureMinEV / MaxEV pinned to the area's own EV, so the
adaptation has no room even when the game's controller (Village: `app.ToneMapController`) switches it back on. NUM7 toggles
it; the Visceral options window's graphics tab has "Let the game adjust the brightness by itself" (bridge slot 174) to compare.

Village is a different case from RE2 and worth watching: the scope work measured the main camera's `get_EV` staying 3.0
indoors and out while the tone-map white points moved with the zone `[measured 2026-10-02]`, so what "adaptive" looks like
here may be the per-zone white point as much as EV. If the pinned limits and Disable do not make the light steady, the next
lever is the zone white points (MinWhitePoint / MaxWhitePoint) or the controller's blend.

Built 7b25cf07 `[compile-verified 2026-10-29]`, installed on top of v1.1.5 + Visceral; backup
`D:/RE Village REFramework builds/_backup-2026-10-29-2209-before-visceral-re8-deploy/`. **Nothing checked live yet**: the
first run's log must show `exposure: Disable = N, kept` and then `kept off (... UseAutoExposure 0, EV x, limits x..x)`.
