# Gold Digger, 2026-11-05: three things the shelved Village logs say that the notes do not

From: `/gd` on the dev PC (PC2), reading the visceral-re8-vr shelves (hands, guns, logs, performance), 2026-11-05.
Nothing here was tested live; every line is read from a shelved log, named so it can be checked.

## 1. Ghost Hand compares the game hand and the controller in two different spaces

`[measured 2026-11-05]` Every Village Ghost Hand report from about 2026-11-01 on gives a "usual" distance between the
game's hand and the real controller of roughly 156 m (95 % mark the same order). A hand cannot be 156 m from the
controller that drives it, so the two positions are being logged in different spaces (one in room space, one in world
space, or one before and one after the player's position is added).

- Newest example: hands shelf item `2026-11-05_12-43-40_PC1_begone-ghost-hand_2026-11-05_12-21-49_openxr`:
  usual gap 156.7 m; the game hand "jumps" 141 m and 57 m at 108.5 s (the player moving, not the hand).
- **Effect:** every Village hand report since then is unusable for racking, magazine and grip questions. The rack /
  magazine / shell event lines in the same reports still read normally; only the distances are wrong.
- Earlier reports (October) had gaps of a few centimetres, so it broke with a change around 2026-11-01. `[hypothesis]`:
  the 10-31 clean REFramework rebuild or the hand-poser rest-pose work changed which transform `ghosthand.cpp` reads.

Proposed board row: `[PD] Ghost Hand: log the game hand and the controller in the same (room) space again; check against
one report that the usual gap is back to centimetres.`

## 2. Three settings files were empty at the 2026-11-05 14:55 launch

`[measured 2026-11-05]` The REFramework log of that launch (logs shelf, 2026-11-05 afternoon copy) reports reading these
as empty, so the features fell back to their built-in defaults:

- `magthrow.json` (the thrown-magazine feature, build b064 of the same day)
- `re8_vr_haptics.json`
- `village_character_joints.json`

Earlier the same way: the Hand Poser pose `ri3036 @ slide from the left.json` was read empty once (gone from the newest log).

Possible causes, not separated yet: a file written by the mod at exit and cut short by a close or crash; a file created
empty by an install step; or the feature writing it only on change. One look at each file's size on the home PC tells
which ones are still empty.

Proposed board row: `[FLAT] Check the three settings files on the home PC; if any is 0 bytes, find who writes it and make
the write safe (write a temporary file, then rename).`

## 3. The scope runs without the patched REFramework (the scope's own repo has the detail)

`[measured 2026-11-05]` Every `re_scope_vr_session.log` copy on the shelf (2026-11-04 17:18 to 2026-11-05 12:43, 20 copies)
says `REF_GetMirrorDrawPose missing -- the crosshair maths keeps the camera joint's pose`. The first copy already held 15
such lines, so it began before shelving started. Written up in `re-village-scope-vr/engine-research/inbox/` as well, since
the fix belongs to whoever owns the REFramework build both mods share.

## Minor

- `[measured 2026-11-05]` 2026-11-02 01:33: one `IndexOutOfRange` in `via.Transform.get_Position` with "VMContext
  corrupted" in the REFramework log; seen once, no crash followed.
- The 2026-11-04 17:34 crash is already in the shop notes; nothing new about it on the shelves.
