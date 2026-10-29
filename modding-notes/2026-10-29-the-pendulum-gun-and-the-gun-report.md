# 2026-10-29 (afternoon) — the "wrong gun" is a pendulum, and a report that measures it (home PC, Fable, desk)

## The sighting, in Tefa's words (asked today what "the guns are wrong again" of 10-25 23:10 looks like)
*"1 the gun only 2 gun is too low, it's like my right hand is just above the gun and when i rotate my wrist the gun
swings like a pendulum instead of a wrist and hand rotating naturally"* `[reported 2026-10-29]`. The picture is at the
right height. So the board's lead ("REFramework's standing origin, sitting vs standing") was the wrong family: a wrong
origin moves the view too. This is a PIVOT fault: the wrist turns about a point some centimetres ABOVE the gun; on a good
launch that distance is zero.

## How the gun gets into the hand (praydog's RE8VR.cpp, read today)
`update_hand_ik`: each frame the right hand's IK TARGET transform is set to the controller's pose (camera space) plus
`m_right_hand_position_offset` and `m_right_hand_rotation_offset`; the arm chain is put in a T-pose and the game's own
two-bone IK (`app.AnimIK2Bone.calc`) reaches for the target. Nothing in that file positions the WEAPON: the gun rides the
hand joint by the game's own attachment. So a pendulum means one of:
1. the game's hand-to-weapon attachment is in another state (its aim-stance pose; the 10-25 21:45 reference run was the
   first with `AIM_OFF = true` and the gun "aimed right");
2. the arm cannot reach the target (the hand lands short of the controller: the gun pivots about the controller's pose
   while hanging where the hand is);
3. a per-launch read of ours failing (Dock Poser "pose of: no gun", the grip script's live socket).
Nobody has measured which, because the bad launch's log was always overwritten by the next one.

## What was built: `gunreport.cpp` (visceral_re8_native, installed)
While a gun is in hand, every 5 s and at once when the gun moves 2 cm in the hand's own frame, one line:
`gunreport: <weapon> | aim A hands H reload R left-docked D | target->hand N cm (hand N cm BELOW/above the target) |
hand->gun root N cm, in the hand's frame x y z cm (gun N cm BELOW/above the hand) | reach: shoulder->target N cm, arm N
cm [OUT OF REACH] | praydog's hand pos vs the IK target N cm`
- the hand joint and the arm come from the IK object's own joint hashes (`<HashJoint0/1/2>`: upper arm, forearm, hand);
- "in the hand's frame" is the number that must be the same on every launch; a good evening gives the reference, a bad
  evening shows what moved: the gun against the hand (1 or 3) or the hand against the target (2);
- the lines also go to `reframework/data/visceral_re8/gunreports/gunreport-<date>-<time>.txt`, one file per launch, so
  the bad launch is kept whatever REFramework's log does.

## What to do on the next bad launch (Tefa or a session)
Nothing extra: play as usual, then say which launch was bad. The session reads that launch's gunreport file against a
good one's, and the fix follows the number that moved.

## Flat smoke test `[verified-live 2026-10-29 flat, n=2 runs]`
First run: the hand read 55 m from the gun: the Motion's joint poses are in the PLAYER'S frame, not the world's (fixed: turned
with the player transform), and the change trigger wrote a line every frame (now at most one a second). Second run, pistol
in hand, flat (praydog's target stale since no headset): `target->hand 9 cm | hand->gun root 15 cm, in the hand's frame
-3.6 -9.2 10.4 cm | reach: shoulder->target 31 cm, arm 55 cm`, no error, the dated file written. "praydog's hand pos vs the
IK target" reads nonsense flat (his hand position is only set with a headset): read it in VR only.
