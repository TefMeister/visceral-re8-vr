# REFramework takes the standing origin from the head at VR start, and again on every runtime recenter

**Date:** 2026-10-26 (`/gr`, FULL pass) · **Status:** 🆕 new · **For:** the top `[PD]` row, "THE GUN WRONG AGAIN THE
NEXT LAUNCH", whose lead is `[hypothesis]`: *"REFramework's standing origin is taken when VR starts (not saved,
VR_SetStandingOriginKey unbound), so a launch sitting vs standing puts the body at another height"*.

## What REFramework's source says

`[inferred-static 2026-10-26]`, read in GitHub's viewer from praydog's REFramework master (`src/mods/VR.cpp`,
`src/mods/vr/runtimes/VRRuntime.hpp`, `src/mods/vr/runtimes/OpenXR.cpp`):

1. **At VR start the origin is the head, all three axes.** The runtime starts with a "reset the origin" flag already
   set; on the first frame with valid poses REFramework sets the standing origin to the headset's position at that
   instant and clears the flag. Nothing reads a saved origin from the config. So the lead's first half is right: the
   height is simply wherever the head was when VR came up.
2. **A runtime recenter does it again.** On OpenXR, when the runtime reports a reference-space change (the event a
   runtime sends when the user recentres, for example from the headset's own menu or Virtual Desktop's recenter), the
   same flag is set and the origin is retaken from the head. So the height can change in the middle of a session, not
   only between launches. `[hypothesis]` that Virtual Desktop's recenter raises that event in this setup; the code path
   itself is certain.
3. **The menu has two buttons, one of which keeps the height.** "Set Standing Origin" (and its key) takes all three
   axes from the head; "Set Standing Height" takes only the height. "Recenter View" changes only the facing.
4. **Lua can read and write it.** `vrmod:get_standing_origin()` / `vrmod:set_standing_origin(Vector4f)` are part of the
   documented Lua API (the community REFramework book lists both). praydog's own `re8_vr.lua`, as shipped in this
   project, already calls `set_standing_origin` for roomscale movement, and it carries the old height over, so it never
   changes the height itself.
5. **The C plugin API has no VR origin call** (nothing about standing or recenter in `include/reframework/API.h`), so a
   native fix goes through the Lua bridge.

## What it means for the gun

- It supports the lead: two launches in different poses give two body heights, and with the controllers placed
  relative to the head, the arm's reach to the controller differs, which can tilt the gun. ⚠️ It does not prove the
  tilt comes from the reach; the read in the board (arm IK stretching or folding) is still the step to measure.
- **"Regardless of sitting or standing" has a ready route:** pin the height. Save the height from a good run (the
  standing origin's y, plus a note of the pose), and after the first valid poses, and after any later change, write it
  back with `vrmod:set_standing_origin`, keeping x and z as REFramework has them. A recenter then cannot move the body
  up or down. The other half of the board's real fix (turn the gun from the controller alone, never from the arm's
  reach) stays the stronger cure; pinning the height removes one of the two moving parts while that is built.
- Cheap check first: log the standing origin's y once at start and every few seconds; two launches in two poses should
  show two numbers, and a recenter should show a jump.

The same layer runs on RE2, RE3 and RE7 (praydog's REFramework VR), so the same pinning applies to the sibling
Visceral projects.

## Sources

- praydog, **REFramework** (VR mod source) — <https://github.com/praydog/REFramework>
- cursey and contributors, **REFramework book**, `vrmod` Lua API page —
  <https://github.com/cursey/reframework-book/blob/main/src/api/vrmod.md>

No code was copied; the behaviour is described in our own words.
