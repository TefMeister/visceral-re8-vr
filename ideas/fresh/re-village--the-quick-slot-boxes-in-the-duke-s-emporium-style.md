# The quick-slot boxes in the Duke's Emporium style

Order: 4019
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-10-27

`[raw]` · `[not judged]` — *not checked against the game's UI yet*

**What Tefa said (2026-10-27):** the D-pad weapon menu (left thumb rest + right stick diagonal) has four boxes; each
should look like something out of the Duke's Emporium: a stylised rectangle background, a nice script font, and the
weapon slightly raised in front of its box.

**What it'd take:** the cross is `app.GUIQuickEquip` (slots `c_top/c_right/c_bottom/c_left`), already moved by
`visceral_re8_hud.lua`. The Duke's shop has its own GUI with these frames and fonts, so its textures / font may be
reusable on the cross's elements; the raised weapon is the slot's weapon icon moved forward (or a 3D copy of the gun,
which the zone spheres already make). Unchecked. `MODEL: OPUS` to look, `MODEL: FABLE` if the GUI needs new drawing.

Verbatim record: [`inbox/2026-10-27-village-dukes-emporium-quickslot-and-item-pickup.md`](../inbox/2026-10-27-village-dukes-emporium-quickslot-and-item-pickup.md)
