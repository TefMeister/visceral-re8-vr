# /gr: the standing origin is retaken from the head at VR start AND on every runtime recenter

From: `/gr`, 2026-10-26 (estate sweep, FULL pass).

**The board row:** `[PD]` "THE GUN WRONG AGAIN THE NEXT LAUNCH", lead `[hypothesis]`: *"REFramework's standing origin
is taken when VR starts (not saved, VR_SetStandingOriginKey unbound), so a launch sitting vs standing puts the body at
another height"*.

**Answer** `[inferred-static 2026-10-26]`, from REFramework's public source: yes, at the first valid poses the origin is
set to the headset's position (all three axes) and nothing is read back from the config; AND on OpenXR it is retaken
the same way whenever the runtime reports a reference-space change (a recenter), so the height can also change
mid-session. "Set Standing Height" (menu) takes only the height. Lua has `vrmod:get_standing_origin()` /
`vrmod:set_standing_origin(Vector4f)`; the C plugin API has no VR origin call. Topic:
[`external-research/topics/2026-10-26-the-standing-origin-is-taken-from-the-head-at-vr-start-and-on-every-recenter.md`](../../external-research/topics/2026-10-26-the-standing-origin-is-taken-from-the-head-at-vr-start-and-on-every-recenter.md).

**Suggested change:** the lead's first half can move from `[hypothesis]` to `[inferred-static]`, with the recenter path
added. A height pin (save y from a good run, write it back through the Lua bridge after the first poses and after any
change, x/z left alone) is a cheap stop-gap beside the real fix; log the origin's y every few seconds first to see it.
