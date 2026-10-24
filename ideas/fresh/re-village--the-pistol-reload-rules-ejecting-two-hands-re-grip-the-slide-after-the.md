# The pistol reload rules: ejecting, two hands, re-grip, the slide after the last round

Order: 4007
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-10-25

`[raw]` · `[looks doable]` — *all of it is reload.cpp / rack.cpp logic the plugin already tracks (2026-10-25); unbuilt*

> "when ejecting a mag, left hand should not be able to dock and if holding two hands on the grip while ejecting the mag, two hands must still stay on until LG is released, after which it cannot grip the pistol again before new mag has been inserted. when the pistol is not empty, mag changed mid way through, the slide cannot be open when ejecting the mag. only when the last round has been shot, the slide must jump back and stay that way until pulled back further after a mag insert, and released to jump forward, without the player hand travelling with the slide"

Verbatim record: [`inbox/2026-10-25-re8-pistol-reload-rules.md`](../inbox/2026-10-25-re8-pistol-reload-rules.md)

**What it'd take:** five rules in the plugin: (1) no two-handed grip may start while a magazine is out; (2) a grip held when
the mag drops stays until LG is let go; (3) no new grip until a magazine is in; (4) the slide only locks back when the last
round was fired (a mid-magazine change keeps it closed); (5) after a mag insert, pulling the locked slide a little further
and letting go sends it home by itself, the hand staying where it is.
