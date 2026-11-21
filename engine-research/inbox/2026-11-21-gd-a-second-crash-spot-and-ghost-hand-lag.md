# Village: a second crash spot on 2026-11-14, and Ghost Hand's hand-lag lines (Gold Digger, Keeper full scan 2026-11-21)

## 1. A crash at re8.exe+0x49F5794, 2026-11-14 22:46

REFramework's crash dump of the run that ended 2026-11-14 22:46:34 (`crashes/...22-46-34..._reframework_crash.dmp`;
the run's events say "crashed (exit code 0xC0000005)" at minute 35) puts it at **`re8.exe+0x49F5794`, reading
address 0x220 (a null pointer)**. Steam was still loaded [measured 2026-11-14, crash shelf].

The notes of that night record a different crash: commit "Holster marker spheres only for Holster Zones' open row (a
sitting marker made during a load crashed at re8.exe+0x415879c)", at 23:34, later and at another spot. The one at
22:46 is not written up anywhere. `[hypothesis]` A read of 0x220 off a null pointer looks like a game object that
was already gone, for example during a load. That would be the same family as the marker crash.

Proposed board row: say which build ran at 22:46 (the seated holster evening), and whether `+0x49F5794` is the same
load-time read as `+0x415879c`.

## 2. Ghost Hand: the game's hands trail the controllers by 7 to 12 frames

The Ghost Hand reports of 2026-11-14 and 2026-11-17 say:
- 21:56: the left hand trails by 12 frames (187.8 ms);
- 22:04: the left hand trails by 7 frames (106.5 ms), and the game's hand jumped 700 times while the controller was
  calm;
- 23:29: both hands trail by 12 frames (191.3 ms), with 537 jumps;
- 17 November 21:06: the right hand trails by 3 frames and the left wanders up to 126 cm, with 1,064 jumps.

The report of 2026-11-16 17:03 itself warns: "Numbers not to be trusted: ... the two were logged in different spaces
(world and room)". `[hypothesis]` The 14 November reports may have the same fault, since docking the hands to the gun
moves them far from the controller. Read them with `begone.py report ghost-hand <id>` before believing a 190 ms lag.
If they are right, 190 ms is far more than a hand can trail and still feel like it follows.

Proposed board row: check whether the 14 November Ghost Hand numbers were logged in one space. If they were, find
where the 7 to 12 frames of trail come from.
