# Wireframe zones with a docking arrow inside, one colour per weapon part

Order: 4016
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-10-30

`[raw]` · `[hard]` for the wireframe and the arrow, `[looks doable]` for the colours — *checked against the zones script on 2026-10-30, nothing tried in the game*

**What Tefa said (2026-10-30):** the solid spheres are not good enough to rely on. Each zone should be a wireframe ball
with an arrow inside it that points the way the hand will dock, and each weapon part (slide, magazine, front grip, pump,
bolt...) gets its own colour.

**What it'd take:** (1) colours: the script already tints every sphere through its material's colour variables (white
grip, orange landing spot, written 2026-10-29, not yet seen in the headset); if that tint shows, a colour per part is a
small table. If it does not, the colour variable names from the log are the next step. `MODEL: OPUS`. (2) the wireframe
and the arrow: the zones are drawn as game meshes (a test ball, or a copy of the gun), and every mesh loaded fresh from a
file has drawn nothing in five tries, so a wireframe ball and an arrow would have to be a mesh the game already ships
(a wire cage prop, a direction marker) or a shape built from many small balls (the beads between START and LAND already
are). The arrow must turn with the dock direction (zone centre to landing spot), which the script knows. `MODEL: FABLE`
to find a way to draw a shape that is not a ball.

Verbatim record: [`inbox/2026-10-30-re8-wireframe-zones-with-arrows-and-part-colours.md`](../inbox/2026-10-30-re8-wireframe-zones-with-arrows-and-part-colours.md)
