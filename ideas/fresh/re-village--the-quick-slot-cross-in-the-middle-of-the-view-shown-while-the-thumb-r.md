# The quick-slot cross in the middle of the view, shown while the thumb rests, only the chosen slot

Order: 4005
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-10-24

`[raw]` · `[looks doable]` — *the cross's parts are known (2026-10-24); unchecked for the rest*

> "the ui has to move to the center of the screen later, so things are clearly in the corners of the screen and maybe we can tweak it so that only the selected one shows up not all of them, maybe we can set it up so that the thumb on the thumb rest makes the d-pad selection visible for as long as thumb is on it - that would be awesome actually!"

Verbatim record: [`inbox/2026-10-24-re8-quickslot-hud-thumbrest.md`](../inbox/2026-10-24-re8-quickslot-hud-thumbrest.md)

Three wishes: the cross centred so its four corners sit clearly in the corners of the view; only the selected slot drawn;
and the cross shown for as long as the left thumb rests on the thumb rest. **What it'd take:** the cross is
`app.GUIQuickEquip` (panel `c_layout`, slots `c_top/c_right/c_bottom/c_left`), already moved onto the diagonals by
`visceral_re8_hud.lua`; centring is its position, "only the chosen one" its other slots' visibility, and the thumb rest is
already read (`_G.__visceral_thumbrest_dpad`), so it can open the cross through the game's own `openQuickEquip`.
