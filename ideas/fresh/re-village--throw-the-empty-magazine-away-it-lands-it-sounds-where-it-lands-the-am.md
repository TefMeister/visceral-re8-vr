# Throw the empty magazine away: it lands, it sounds where it lands, the ammo count never changes

Order: 4023
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-11-05

`[raw]` · `[looks doable]` — *checked against our own code only, 2026-11-05; the landing sound unchecked*

> "throwing away a used mag, the ammo count should not change if it is even partially full as that messes with game's systems and changes the actual game, but for show, and that sound would also play from where it lands"

Verbatim record: [`inbox/2026-11-05-village-five-feasibility-asks.md`](../inbox/2026-11-05-village-five-feasibility-asks.md) (point 1)

**What it'd take:** half of it is built. A magazine let go of already drops, and its rounds already stay counted (Tefa's own ask of 2026-10-25, in the reload code). Today it simply falls for half a second. Missing: carrying the hand's speed into the throw, finding the floor under it so it stops there, and the clatter played at that spot. The sound is the uncertain part: the game plays sounds on an object, so it needs an object at the landing spot (the dropped magazine itself, if the game treats it as one), not yet checked.
