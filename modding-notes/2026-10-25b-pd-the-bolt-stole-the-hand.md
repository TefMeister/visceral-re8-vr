# 2026-10-25b: the bolt stole the hand (the last wear's log, read; the fixes built and installed)

No game running. The log of the 03:48 build's wear (kept as `D:\RE Village REFramework builds\logs\re2_framework_log-2026-10-25-0354-last-wear.txt`)
explains all four of Tefa's 04:00 complaints. Build b5d20f59, installed 08:55 (backup `_backup-2026-10-25-0855-before-visceral-re8-deploy`).

## What the log showed `[measured 2026-10-25]`

1. **"The mag jumps back in after I take it out."** Every pull-out was followed within 0.1 s by
   `the magazine is clear of the well (0.126 m)` and, the same frame, `insert at 0.126 m (need 0.16)`. The clear distance
   (`INSERT_CLEAR_M` 0.12) lay INSIDE the long gun's insert distance (`DOCK_ITEM_M` 0.16), so "clear" and "back in" were one
   moment. Twelve pull-outs in 11 s at 03:53, each re-seated at once (Tefa hammering LT).
2. **"Hand still gripped on the rifle grip handle alongside the right hand."** Not the grip script: it took the grip ONCE, on the
   forestock (socket 0.39 m from the right hand, so the 25 cm long-gun rule held), and the game's own dock answered 0 asks (off).
   It was the RACK: the F2's bolt joint (its "Slide", gun-local 0, 0.088, 0.018) sits 13 cm from the magazine joint (0, 0.021,
   0.131). The bolt zone was 14 cm around that joint measured from the CONTROLLER, which sits ~15 cm behind the drawn hand, while
   the magazine zone is 12 cm measured from the drawn hand (the left IK target). So a reach for the magazine that missed by a few
   cm (0.122-0.18 m, 03:52:14-32) was taken by the bolt ("HAND ON" at 0.140 from the joint), and the hand was held up at the bolt,
   beside the right hand.
3. **"Very hard to get it to dock on the mag."** The grabs that worked measured 0.080, 0.111, 0.102, 0.100, 0.104, 0.112, 0.118 m
   (drawn hand to magazine joint): 0.12 is the right zone. The misses were the bolt trap above: once the bolt held the hand, the
   drawn hand WAS at the bolt, 0.13-0.18 m from the magazine, so every further LG press missed until LG was let go.
4. **"The bolt activation area is too large."** The same 14 cm controller-measured zone.

## Built `[compile-verified 2026-10-25]`

- `settings.h`: `INSERT_CLEAR_MARGIN_M` 0.10 replaces `INSERT_CLEAR_M`; `RACK_BOLT_GRAB_M` 0.09 new.
- `reload.cpp` hand_checks: a pulled-out magazine is clear only past the insert distance + 0.10 (long gun 0.26 m, pistol 0.34 m);
  the log line says both numbers.
- `rack.cpp`: the bolt is measured from the drawn left hand (the IK target, the magazine's point) with the 9 cm radius; the slide
  and pump keep the controller and 14 cm (Tefa: "shotgun is fine now!", untouched). The near log line names the joint and the
  point measured from.
- Nothing changed in the grip script or nodock: they did their job.

## For the next wear

Rifle: LG on the magazine (within 12 cm), LT: it comes out and STAYS out while the hand is near the well; it goes back in only
after the hand has been 26 cm away first (log `clear of the well (... needed 0.26)`). Reaching for the magazine and missing no
longer puts the hand on the bolt; the bolt takes only within 9 cm of its handle (log `from the bolt joint (need 0.09, the drawn
hand)`). The hand next to the right hand should be gone. Not yet looked at: the pistol rules from mod-ideas (board row).

## 09:20, Tefa: "can this be set so that LT must be pressed again for it to go back in, that would solve this problem for good"

Agreed and built (a3bf6318, installed 09:40, backup `_backup-2026-10-25-0940-before-visceral-re8-deploy`). The 26 cm clear rule is
gone. A magazine pulled out by hand now sits at the well, however close, until a fresh LT press while it is at the gun (`INSERT_NEEDS_LT`;
the pull-out's own press cannot count: 0.25 s wait, `INSERT_LT_MIN_SEC`). Log: `the pulled-out magazine is at the well (...): press LT
to seat it` every 2 s while it waits, then `LT pressed at the well: the pulled-out magazine goes back in`. A fresh magazine from the
pouch still seats by itself when brought to the gun (unchanged; LT there too if Tefa wants it).
