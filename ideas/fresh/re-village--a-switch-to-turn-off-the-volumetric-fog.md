# A switch to turn off the volumetric fog

Order: 4050
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-11-05

`[raw]` · `[looks doable]` — *the fog parts seen live by the scope work 2026-10-03; switching them off not tried*

> "option to disable volumetric fog, it is performance heavy"

Verbatim record: [`inbox/2026-11-05-village-five-feasibility-asks.md`](../inbox/2026-11-05-village-five-feasibility-asks.md) (point 4)

**What it'd take:** the game has no fog setting of its own (not in its settings file). The fog lives in parts on the camera (VolumetricFog, VolumetricFogControl), seen live on 2026-10-03 by the scope mod. A switch in our options that turns those off, on the main camera and the scope's camera alike (or the scope picture stops matching), and puts them back when unticked. Watch for: Village's look leans on its fog, so some places may look flat or too clear.
