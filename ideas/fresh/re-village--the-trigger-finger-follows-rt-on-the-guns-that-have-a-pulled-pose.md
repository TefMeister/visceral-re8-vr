# The trigger finger follows RT, on the guns that have a pulled pose

Order: 4007
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-10-28

`[raw]` · `[looks doable]` — *not checked against the code: Hand Poser keeps still poses only (one per gun and spot), and nothing moves a right finger on RT today (2026-10-28)*

> "and how do i get to animate finger poses? my idea is that pressing RT only when the a specific gun is out makes the trigger finger move, is that possible? i'm guessing it is, but no idea"

Verbatim record: [`inbox/2026-10-28-re8-trigger-finger-follows-rt.md`](../inbox/2026-10-28-re8-trigger-finger-follows-rt.md)

**What it'd take:** a second right-hand pose per gun in Hand Poser, "trigger pulled", posed once with Hand Freeze holding the
hands; RT's travel (0 to 1, from the bridge) blends the right index finger from the gun's normal pose to the pulled one each
frame, written the way `fingers.cpp` writes the left fingers. A gun with no pulled pose saved does nothing, which is the "only
when a specific gun is out" part. The same blend is the general answer to "animate a pose": two still poses and something
that moves between them (RT here; the bolt stage and magazine distance in the entry above).
