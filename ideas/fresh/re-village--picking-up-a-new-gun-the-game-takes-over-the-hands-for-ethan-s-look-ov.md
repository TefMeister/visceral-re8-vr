# Picking up a new gun: the game takes over the hands for Ethan's look-over

Order: 4030
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-11-05

`[raw]` · `[looks doable]` — *unchecked; the animation itself not yet found by name*

> "when picking up a new gun, game has to take over hands entirely for the new gun pick up animation the game plays, where Ethan inspects the gun first"

Verbatim record: [`inbox/2026-11-05-village-five-feasibility-asks.md`](../inbox/2026-11-05-village-five-feasibility-asks.md) (point 3)

**What it'd take:** spot when that animation starts and ends (by its motion number or its sounds, which the sound script already learns), and for that long switch off everything of ours that moves the arms and hands, the way Hand Poser already stands aside while a finger clip plays. One flat run to find the animation. Watch for: the hands may play where the flat camera would be, not where the head is.
