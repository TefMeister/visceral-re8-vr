# Hands-on magazines on the long guns; B ejects only on pistols; a faint glow on the parts to work

Order: 4008
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-10-25

`[raw]` · `[looks doable]` — *the magazine states, the hand-carried mag, the pouch and the drop exist in reload.cpp already (2026-10-25); the glow needs a probe of the guns' material names first*

> "with select guns, like the rifle, work around the whole game's system of reloading, meaning to reload the rifle, i have to put my left hand on the mag, press LT to release it, then i can throw it on the ground and non-spent bullets will still be in my inventory, then put a new mag in and continue. so B only ejects the mag on pistols and we'll make a thumb flick to make it a visible button press ... a faint glow system to get used to these manual reload systems, so the parts that need working will glow faintly, we'll pick a colour later"

Verbatim record: [`inbox/2026-10-25-re8-manual-mags-and-glow.md`](../inbox/2026-10-25-re8-manual-mags-and-glow.md)

**What it'd take:** a new way INTO the existing magazine reload: the left hand on the magazine joint with LG held, then LT,
detaches the magazine into the hand (the hand already carries one after a B eject; the drop, the rounds kept, the pouch and
the insert are all there); B keeps working only on pistols. The glow: the guns' mesh parts are already known by name
(`log_parts`); a faint emissive on a part's material (RE Engine material variables, read live with REFramework) while that
part is the next thing to work, off when done; which variable names the gun materials expose is the first check.
