# 2026-10-25 evening — the right grip holds the gun, no aim; rack from the grip zone; numbered hand pairs (home PC)

## Built and worn
- `visceral_re8_holsters.lua`: letting go of the right grip puts the gun away (Andyalpa's proven stow, exported by
  `re8_vr_holster.lua` as `__re8_holster_stow_to_bare`); `AIM_OFF = true`: the grip no longer presses the game's aim, hip
  fire throughout (flat: "RT alone fires from the hip", KNOWN.md 2026-10-24).
- With the aim stance gone, the gun aimed right for the first time: "this is how the gun is naturally in the player hand and
  should always be like this" `[verified-live 2026-10-25, n=1]`. Every gun-in-hand setting of that run kept in
  `dev-archive/reference/2026-10-25-gun-aims-right/`. The next launch it was wrong again with every setting the same; lead:
  REFramework's standing origin taken at VR start (sitting vs standing) `[hypothesis]`.
- `rack.cpp`: a rack due + a fresh LG inside the FRONT GRIP zone sends the hand onto the slide / pump / bolt with the arc
  ease; worn, log "LG at the front grip with a rack due: the hand goes onto the bolt" `[verified-live 2026-10-25, n=1]`.

## The crash and the spheres
- 22:06 crash: picking the "no material" sphere look remade the spheres, the remake's setMesh threw five times, then an
  access violation (re8.exe+0x415879c). Fixed: one look only, "axis", in the game menu and the Grab Zones window.
- The drawn spheres ignore their size: the log had every number right while nothing grew or shrank `[verified-live
  2026-10-25, n=1]`, the same as "they disappeared when I changed the size". Cause not found (`MODEL: FABLE`).

## Numbered hand pairs (new, unworn as a whole)
- `src/pairs.cpp` + the Grab Zones HAND PAIRS box (`PairsBox.cs`): each pair a number, a name, a gun, an activation sphere
  and a landing spot (offsets from the gun hand in the gun's axes, `data/visceral_re8/pairs.json`). A fresh LG inside the
  start sphere sends the left hand (smooth.cpp owner PAIR, arc ease) to the landing spot while LG is held. Bridge slots
  142-152 (S_COUNT 153). First try: positions right in the log; sliders lengthened to -60..+100 cm; beads hidden.
- Not done: a pair triggers no action by itself (it places the hand).
- The clear-all buttons are gone from the window and the in-game menu (Tefa: afraid of pressing them by accident).
