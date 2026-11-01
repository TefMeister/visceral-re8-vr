# The right hand swaps the rifle's magazine while the left holds it

Order: 4015
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-11-01

`[raw]` · `[looks doable]` — *judged from the mod's code only (2026-11-01): the rifle held by the left hand already works for the right-hand bolt, and the right hand taking rounds from the left-hip pouch is being built for the Wolfsbane the same evening; not tried*

**What Tefa said (2026-11-01):** the same as the Wolfsbane's right-hand loading, for the rifle: with LG + LT holding the rifle in
the left hand, RG + RT ejects the magazine, RG at the left hip takes a new one, and the right hand brings it to the gun.

**What it'd take:** the rifle held by the left hand (rack_right.cpp) and the right hand's pouch grab (gate.cpp, the Wolfsbane) both
exist by then; the new part is the magazine following the RIGHT hand instead of the left (reload.cpp draws it in the left hand
today) and the RG + RT eject. `MODEL: OPUS`.

Verbatim record: [`inbox/2026-11-01-village-right-hand-rifle-magazine.md`](../inbox/2026-11-01-village-right-hand-rifle-magazine.md)
