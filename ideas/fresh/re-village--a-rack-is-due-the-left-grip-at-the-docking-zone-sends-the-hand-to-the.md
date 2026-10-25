# A rack is due: the left grip at the docking zone sends the hand to the slide or bolt

Order: 4012
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-10-25

`[raw]` · `[looks doable]` — *checked against the code on 2026-10-25 (rack.cpp's take, smooth.cpp's arc), not tried*

**What Tefa said (2026-10-25, in the headset):** instead of the left hand simply not docking on the gun while it needs
racking, the left grip pressed in the docking zone should send the hand onto the slide or the bolt by itself: a quick
but smooth hand travel.

**What it'd take:** the pieces exist. `rack.cpp` already takes the slide when a rack is due and the left grip is held near
it; `smooth.cpp` already eases the hand onto the slide with an arc over the gun (the HAND ON THE BOLT box, about 0.3 s);
the front grip is a zone sphere now. The change: with a rack due, a left grip pressed inside the FRONT GRIP zone counts
as a take of the slide / bolt, and the ease carries the hand there. Today a hand that came from the grip dock waits for
the grip to be let go (Tefa's 2026-10-25 15:39 report), so that rule must allow this one case.

Verbatim record: [`inbox/2026-10-25f-village-lg-at-grip-goes-to-the-slide-when-rack-due.md`](../inbox/2026-10-25f-village-lg-at-grip-goes-to-the-slide-when-rack-due.md)
