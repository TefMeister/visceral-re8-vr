# The game's own left-hand animation plays for the insert, the right hand stays still

Order: 4018
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-10-31

`[raw]` · `[hard]` — *judged from the mod's code only (its "let the game do its own reload" experiment), not tried in the game*

**What Tefa said (2026-10-31):** when a magazine, shell or clip goes in, the left hand should play the game's own reload
animation, while the right hand (and the gun) stays still where the controller holds it.

**What it'd take:** the mod can already let the game's own reload run (an experiment switch), but that animation moves the
whole body and both arms, and praydog's hand code puts both hands on the controllers every frame. So: during the insert,
let the game's reload play, read where its LEFT hand is against the gun it animates, and put our left hand at that same
place on the gun the player holds (the right hand stays on the controller), then hand the left hand back. Unknowns: whether
the insert part of the game's animation can be started on its own (or the full reload skipped to it), and how the round count
stays ours. A Fable job to find out. `MODEL: FABLE`.

Verbatim record: [`inbox/2026-10-31-re8-game-left-hand-animation-for-the-insert.md`](../inbox/2026-10-31-re8-game-left-hand-animation-for-the-insert.md)
