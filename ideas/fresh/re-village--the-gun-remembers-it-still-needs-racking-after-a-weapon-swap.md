# The gun remembers it still needs racking after a weapon swap

Order: 4002
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-10-24

`[raw]` · `[looks doable]` — *checked in our code 2026-10-24*

> "game to remember reload state - so when a rifle needs racking then after i switch to a different gun and switch back, it will still require racking - right now it doesn't."

Verbatim record: [`inbox/2026-10-24-re8-visceral-fifteen.md`](../inbox/2026-10-24-re8-visceral-fifteen.md) (point 3)

**What it'd take:** our rack code forgets the "needs racking" state the moment the gun changes (it clears it on every swap). Keeping it per gun is a small change.
