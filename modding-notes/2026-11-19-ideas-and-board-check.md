# 2026-11-19: the 47 fresh Village ideas against the board and the code; the board's stale rows; code shape

By the /lm session's reader (read only), 2026-11-19, Fable session. Everything is `[inferred-static]` unless it quotes the
board. Line numbers are of `claude-memory/status/visceral-re8-vr.md` AS IT STOOD BEFORE the ticked rows were moved out of the
OPEN block the same morning (they no longer match; search by the quoted words). Not checked: the game itself, the Hand
Poser / Grip Zones repos, the ideas' full text.

## The ideas (number as in `ideas.py list visceral-re8-vr`)
1 DONE: a rack due survives a weapon swap (simulator 2026-11-01; worn, Tefa "still needs racking to shoot"). Open: the slide does not look locked back after the swap.
2 NOT STARTED: kick boxes.
3 PARTLY: four holster spots, thumb-rest D-pad and the cross built; Tefa "(15) the holsters work". Missing: the diagonals for Tefa, the six-spot layout, our own native holster code.
4 NOT STARTED: the calm start.
5 PARTLY: the cross is drawn with labels; "only on the thumb rest" and "only the chosen slot" not built.
6 PARTLY: the pose points exist (b085); the poses are Tefa's to make.
7 PARTLY: keep-my-view built (b117); worn 2026-11-15: the game still takes the camera; wanted: left / right only.
8 PARTLY: much built and worn (slide closes by itself, magazine by hand, B ejects only on pistols); the full rule set is an open [PD] row.
9 PARTLY, maybe done: the game's left-hand dock taken out ("no jumps now", 2026-10-25); never closed by Tefa.
10 PARTLY: built in b085 (in Hand Poser's script), not worn.
11 PARTLY: hands-on magazines built; the glow not built.
12 PARTLY: three builds; worn 2026-11-15: "still doesn't" turn like Leon's. Open.
13 NOT STARTED: the body in cutscenes.
14 PARTLY: shell size sliders, slide on magazine-in; the chambered round's own count open.
15 PARTLY: rubber arm b085, a held grip stays; not worn.
16 NOT STARTED: yellow tape colour. 17 NOT STARTED: boxes glowing (a probe row only).
18 PARTLY: the right grip holds the gun and the aim is gone = DONE (ticked 2026-11-18); accuracy by hold: magazine handguns only, the headset measurement still to shoot.
19 BUILT, THEN TAKEN OUT ON TEFA'S WORD (2026-10-30: "please remove the feature where hand on the grip goes to the bolt when it needs racking ... actually distracting"): ask whether the idea is still wanted.
20 PARTLY, mostly done: the torch in the hand, "feels awesome"; the beam's jump and wobble (b136 / b137) unworn.
21 DONE: numbered hand pairs (ticked 2026-11-18); colours and numbers shown in the game not built.
22 NOT STARTED. 23 PARTLY: doors by hand b138-b144, waiting for the wear (`[ID RE8-001]`).
24 DONE: the right hand racks the rifle's bolt ("this is epic. really is").
25-30 NOT STARTED (26, 30: wanted later, grabbing a sphere / wireframe + arrow).
31 DONE with a substitute: our own empty click (the revolver's hammer sound).
32 PARTLY: the game's finger movements on our hands, not worn.
33 NOT STARTED: quick-slot box style.
34 DONE: two shells / two magazines in the left hand (headset 2026-11-15); the GM 79's three ways unanswered.
35 PARTLY: the thrown magazine, simulator only.
36 NOT STARTED: items by hand (probe only).
37 PARTLY: grip blend b085, not worn. 38 PARTLY: the new-gun move b115, off by default, not worn.
39 PARTLY: the performance recorder works flat; the long VR run is not done.
40-42 NOT STARTED.
43 PARTLY: grip holds = done; dodge not built (Village has no dodge of its own).
44 DONE for Village: the Emporium options (ticked 2026-11-18).
45 PARTLY: smoothing per gun and per hand b115, not worn.
46 DONE: shells go in one tap after another (Tefa 2026-11-15).
47 NOT STARTED as a held map; menu tap = the map works.

## The board
- Done this session: every ticked row (88 lines) moved out of the OPEN block.
- Still to do (a [PD] job, `[ID RE8-003]`): the row "EVERY VILLAGE TEST WAITING FOR THE HEADSET" (says "the game holds b087")
  re-cut against b144 with an ID per test; rows overtaken by a later row of the same feature (the Wolfsbane chain b071-b080,
  the revolver drum rows of 2026-10-27, b108's body turn against the 2026-11-15 wear, the b090-b110 "not worn" rows that the
  b134 wear probably answered); rows with dates that have passed ("WEDNESDAY 2026-11-11 / 11-18", "RESUME HERE 2026-11-05",
  "START OF NEXT SESSION ... 2026-10-27"); two rows above the OPEN heading (b066, b099).
- A structure fault: under "Done 2026-10-25" sit about 200 lines of [VR USER] / [PD] / [FLAT] rows from 2026-10-15 to 10-25
  with no tick; outside the OPEN block, so no gate scan sees them, yet they read as open. One line there starts mid-word.
- One contradiction to ask Tefa: the body-turn row ticked done 2026-11-18, while the 2026-11-15 wear says it still fails.

## Code shape (`code-shape-scan.py`)
Ours over 1,500 lines: `lua/re8_vr_holster.lua` 11,385 (about 204 top-level locals; Lua stops loading at 200),
`re8_vr_holster_visuals.lua` 4,156, `re8_vr.lua` 3,016, `re8_vr_hand_gestures.lua` 2,054. Over 800:
`visceral_re8_emporium_shop.lua` 1,474, `src/reload.cpp` 1,089, `re8_vrz_begone_grip.lua` 932, `src/rack.cpp` 892.
Not ours: `dev-archive/original-lua/` (Andyalpa's pack as received) and REFramework's `API.hpp`.
Cheap move-only splits: the holster script's settings / load / save and its menu (from about line 10,669) into their own
files (also takes it off the locals limit); the visuals script's builders apart from its hooks (3,489 on). The board already
plans to replace the borrowed holster script with native code, so no more than those.
