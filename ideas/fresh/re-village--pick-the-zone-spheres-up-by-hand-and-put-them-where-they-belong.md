# Pick the zone spheres up by hand and put them where they belong

Order: 4015
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-10-29

`[raw]` · `[looks doable]` — *not checked against the mod; the hands already know where the spheres are*

> "if possible to be able to pick them up by hand and move them around the 3d space would be awesome"

Instead of sliders in the Grip Zones window: reach into a zone's sphere in the headset, grip it, carry it to
where it should sit on the gun, let go. The number in zones.json follows. The plugin already measures the hand
against every sphere every frame (that is how a grab triggers), so "the hand is inside this sphere and the grip
just closed" is a test it can make; the new part is a move mode where a gripped sphere follows the hand instead
of starting a reload or a rack.

**What it'd take:** a "move the zones" switch (menu or the Grip Zones window) that turns the grip inside a
sphere into carry-it, writes the new offset relative to the gun on release, and keeps the normal grabs off
while it is on. ⚠️ Not checked: whether the plugin's zone offsets are easy to write back from a world point
(they are stored relative to the gun's own axes).

Verbatim record: [`inbox/2026-10-29-re-village-grab-the-zone-spheres-by-hand.md`](../inbox/2026-10-29-re-village-grab-the-zone-spheres-by-hand.md)

---
