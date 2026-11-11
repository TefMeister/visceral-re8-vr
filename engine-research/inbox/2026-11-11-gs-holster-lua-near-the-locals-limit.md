# /gs 2026-11-11: `re8_vr_holster.lua` is at the Lua locals limit

From: `/gs` inside the Keeper PC's `/fullscan` of 2026-11-11 (code-shape scan, read-only).

`dev-archive/native/lua/re8_vr_holster.lua` counts about **204 locals** in one function scope, by the scan's
estimate `[measured 2026-11-11, estimate]`. Lua refuses to load a chunk with more than 200 locals in one function,
with no warning until the game runs the script. The older copies (`dev-archive/original-lua/autorun/`, 202; the
staging split of 2026-10-24, 203) and the saved builds b069 to b083 show the same count, so it has been at or past the
line since at least b069.

What to check (modding lane):

- Is this file still installed and loaded by the current Village build, or is it only kept for reference since the
  native rewrite? If it is not loaded, nothing to do but say so on the board.
- If it is loaded: count exactly with `luac -l -l` (the estimate can be off either way), and if it is over 200, move
  a group of the top-level `local`s into a table (`local S = {}` ... `S.name`), move-only, then test that it loads.

Never split or edit from this lane; this is the hand-off. Rule: `docs/PROTOCOL.md` §6 (code shape).
