# 2026-10-29 — Village's adaptive light held still, and the one-eye golden veil explained (home PC, Fable, Tefa in the headset)

Tefa: *"remove the adaptive lighting from RE8 and 3"*, then, with the first attempt in: *"now i have that golden veil on again"*.

## What was found, live through the RE Engine MCP `[verified-live 2026-10-29, Village]`
- The main camera's `via.render.ToneMapping` keeps **EV = 3 everywhere** (the authored base) and AutoExposure = Enable (0).
  It has no `get_UseAutoExposure` and no AutoExposureMinEV / MaxEV (RE2's levers), so the RE2 port read a made-up answer and
  found nothing to pin.
- The **adapted exposure lives on the graphics card**; `get_SnappedRealEV` shows it only after `calcRealEV()`: 3.00 before,
  6.17–6.46 after, outdoors. That number is the adaptive lighting.
- MinWhitePoint / MaxWhitePoint (11/25 indoors, 7/15 or 5.6/15 outdoors, 2/5 in a dark spot) are the level's per-area
  tone-curve range, rewritten by `app.ToneMapController` from its zone data; pinning them to one value changed nothing
  Tefa could see. BrightAdaptationRate 0.035 / DarkAdaptationRate 0.05 set to 0 every frame froze RealEV at 6.46.
- What Tefa saw at the door (*"more like the colours and haze and a quick gradual change over a second or so"*) is the
  per-area blend of the colour grading (`app.ColorCorrectController` → `via.render.LDRColorCorrect`) and the fog, not
  the eye adaptation.
- **The one-eye golden veil (Single Frame Multipass):** Tefa: *"one eye is darker - left one, and right is brighter. in the
  main menu, left eye open was the correct picture, right eye open had the golden veil."* The veil is what the whole
  picture looked like with the adaptation switched off (fixed EV 3, far too bright outdoors). So under Single Frame
  Multipass the **right eye's pass is drawn without the adapted exposure** `[reported 2026-10-29]`. Same family as RE2 /
  RE7's "different lighting in each eye". Two Frame Sequential has equal eyes but is slow and broke the scope's picture
  and gave lamp reflections in the eyes (Tefa, same night); Village is back on Single Frame Multipass.

## What works (Tefa: *"it works! whatever you did it works!"*) `[verified-live 2026-10-29, headset, n=1]`
`reframework/autorun/visceral_re8_whitepoint.lua` (the name is from the first try; it is the steady-light script), writes
landing in a post-hook on `app.ToneMapController.lateUpdate`:
- `adapt = "hold"`: AutoExposure = Disable (2) and `set_EV(6.4)` every frame: no adaptation anywhere, one exposure for
  both eyes (6.4 = the value the game had settled on outdoors). Both eyes match; nothing drifts.
- `grading = "off"`: the per-area colour grading off (controller and component), the fog left alone (it is in the world).
Settings: `reframework/data/visceral_re8/whitepoint.json` (re-read every two seconds) and the REFramework menu
"Visceral RE8: steady light". The native plugin's `exposure.cpp` is kept but starts off.

## Not done
- Indoors at EV 6.4 is not judged room by room yet (one evening, one route). If a place is too dark or bright: the held
  EV slider, or a per-area EV table keyed by the level's white-point pair.
- RE3 has the RE2-style native switch installed (a9fae9a8), never run. RE3 is RE2's engine generation (it has
  UseAutoExposure and MinEV/MaxEV), so RE2's b192 pin may work there; the "hold" shape is the fallback.
- Why Single Frame Multipass draws the second eye without the adaptation: REFramework's SFM path (praydog). A fix there
  would cover every RE game at once; until then each game holds its exposure itself. `MODEL: FABLE`.
