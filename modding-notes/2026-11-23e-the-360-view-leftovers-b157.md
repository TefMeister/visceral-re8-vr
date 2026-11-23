# 2026-11-23 (late evening, /lm by hand-on, PC1, Opus): the 360 view for the robot, the leftovers; b157

Carries on from `2026-11-23d-the-360-view-third-pass-and-the-nearest-part-rule.md` (same rig: the real headset lying on the desk,
Two Frame Sequential, VR Bench's hands, nobody wearing it; Tefa away, questions once at the end). Sheets: `2026-11-23e-sheets/`.

## (a) The landing rule with a rack really due `[verified-live 2026-11-23, robot, n=1]`

The F2 loaded by robot (pouch -> well, bolt racked), one shot ("rack NEEDED (the bolt after the shot)"), then
`landtest.py ri3042 long zones=mag,bolt toward=0.3`: the magazine from its own middle (three sides) gives the magazine; 30 % from
the magazine toward the bolt gives the BOLT (`the hand is nearer the bolt (for its size): that takes it`); the bolt from its
middle and 30 % toward the magazine give the bolt. As b155 meant: a due rack wins the overlap, not the magazine's middle.

## b157: no dead LG press between a long gun's magazine and its bolt (`rack.cpp`, builds store reload/v0.1.0-b157)

- **Seen** (the blend probe below, the F2 loaded with its bolt home and nothing due): LG pressed between the magazine and the
  bolt, nearer the bolt: the magazine stood back ("nearer the bolt: that takes it, not the magazine"), and the bolt did not take
  the hand either. The press did nothing. Reproduced on b156 with `landtest.py`: 30 % from the bolt toward the magazine (13 cm
  from the magazine, inside its 14 cm reach) -> nothing.
- **Why** `[inferred-static, then run]`: b155's `whichpart::nearest()` asked `rack::part_reach()`, which offered the bolt whenever
  the gun has one; but the rack takes the hand only when it may (`may_rack`: a pump or slide any time, a bolt only with a rack
  due, the gun empty, or mid-cycle; Tefa 2026-10-18). A bolt with nothing to do won the choice and then refused.
- **Now**: one function, `may_take_now()`, is both the frame's `may_rack` and a condition of `part_reach()`: a part that may
  not take the hand is not offered. Run on b157, the F2 loaded and racked: 30 % from the bolt toward the magazine -> the
  magazine `[verified-live 2026-11-23, robot, n=1]`. The bolt from its own middle with nothing due still takes nothing (Tefa's
  rule, unchanged).

## (b) The "pulling" stage on the Samurai Edge and the USM-AI

- **The old tool was the fault**: `hold_at.py`'s `pull<n>` line had its two working steps INSIDE a comment since b148, so every
  `pull60` / `magpull60` pulled all the way out. That is the whole of "magazine in hand, pull 0" on the LEMI, Samurai Edge and
  USM-AI. Fixed.
- **New `tools/sim/pull_probe.py <ri> [spare]`** with `q_pull.lua`: bridge slots 279 (how far out) and 153 (the left spot) read
  every frame (EndRendering) while the hand goes 16 cm down over 3.2 s after B. Read `[measured 2026-11-23, robot]`:
  plain reload, all three guns: spot 4 -> 13 at B, the pull runs 0 -> 0.95-0.99 in small steps over about 13 cm of the hand, then
  out. Spare swap, all three: 17 -> 18 at B, the pull 0 -> 0.96-0.99 smoothly (20 to 61 recorded steps), then 16. **The Samurai
  Edge and the USM-AI have a normal-length line; B does not drop the magazine out.**
- What WAS missing: those two had no pose for "spare in hand, pulling the magazine out" (the carry never reached the stage); the
  window made one from the game's own fingers when the probe first reached it. The LEMI's pose sent to both through the window
  (`hold_at.py pull60` + `pose.py $(posefile.py ri3046 ...)`): now identical to the LEMI's (0 joints differ).

## (c) The blends between stages

- **The spare swap** (`stages.py ri3122`, sheet `ri3122-samurai-edge-spare-swap-blend-on.jpg`): with the Hand Poser window open
  the pull blend is OFF (tuning), so stage pictures show each stage's own pose; `hand_poser/blend_preview.json` (testing only,
  removed after) shows it as a wearer sees it. With it on: docked and the first pulled frame are the same hand (no jump at B), the
  fingers close step by step at 1.5 / 4.5 / 8 cm, then "two magazines in hand".
- **Racking** (new `tools/sim/blend_probe.py <ri> <zone> <sheet> [long]` + `q_blend.lua`: the left spot, LT, and the thumb's,
  index's and middle finger's distance from the wrist, every frame, while `strokes.py` works the part; the Hand Poser WINDOW closed,
  as a wearer has it). F2 bolt, W870 pump, WCX charging handle: every change (free -> ready, LG on, LT, pulled back, LT off, let go)
  went through Hand Poser's ease (0.1-0.4 s, several frames); NO change was written in one go. `[measured 2026-11-23, robot]`
- **What could not be judged**: whether the ease LOOKS smooth. The game ran at about 10 frames a second while the robot drove it
  (30 at rest), and the ease is timed (k = dt / 0.15 s per frame), so at 10 fps most of any change lands in the first frame.
  `os.clock` is wall time here (Windows' C clock). One small thing seen: letting go of the pump passes through the gun's general
  pose (spot 0) for 0.1-0.2 s before "ready at pump": the fingers head one way and then the other. Not changed.

## (d) The right hand: the index finger onto each gun's trigger

- **By numbers** (new `tools/sim/trigfit.py` + `q_trigfit.lua`): the gun's own `Trigger` joint (its pivot) and the index finger's
  PAD (1.2 cm past the last joint) in the gun's frame. The other three fingers are a closed grip on every gun (wrist to their last
  joints 11.8 / 11.5 / 11.0 cm, the pistols' kept grip). Before `[measured]`: the LEMI's pad 1.4 cm down the blade and 1.7 on
  its face (good); the WCX, Dragoon, SYG-12 and M1897 had the pad 4.0 to 5.8 cm UNDER the pivot (below the blade, at the guard's
  bottom); the W870's pad 2 cm across the gun's far side; the M1911 and both revolvers 2.6-3.3 cm in front.
- **Fitted** (new `tools/sim/trigsolve.sh`: `solve.py` in the gun's frame, the last joint 1.2 cm under the pivot and 1.3 cm in
  front, the tip down the blade's face; vars knuckle bend and spread, middle and tip joints), through the Hand Poser window into
  each gun's own pose: F2, WCX, Dragoon, SYG-12, W870, M1897, M1911, Handcannon, Wolfsbane. After: every pad 1.8-2.4 cm down the
  blade and 0.9-2.2 cm on its face, 0.3-1.6 cm across `[measured]`. Pictures from the gun's left, below and in front (sheets
  `ri3049-wcx-trigger-finger-fitted.jpg`, `syg12-wolfsbane-f2-trigger-finger-fitted.jpg`; before: `ri3036-w870-trigger-finger-before.jpg`):
  the index lies in the guard on the trigger, the three fingers round the grip, nothing through the guard by eye. The SYG-12 needed
  a wide spread (knuckle y 25.6) and a straight middle joint; the Wolfsbane a straight middle joint: both look like a finger on a
  trigger. The trigger bend on RT is added on top (`righthand.cpp`), so it bends from the new rest.
- Not fitted: the GM 79 (pad already 0.9 cm down, 1.9 on its face, 1.8 across), the LEMI and the four other slide pistols
  (left as the LEMI's kept grip, which measured right). The three fingers were not changed (no grip joint to measure against;
  the pictures show them wrapped).

## (e) A long gun's magazine carried, shells in the hand

- WCX, the magazine pulled out with LT and carried (`ri3049-wcx-magazine-carried.jpg`, four sides, close): the fingers wrap the
  magazine's body, it lies against the palm. Not changed. (In the gun's Magazine frame the hand reads 15-20 cm away: that frame is
  the seated joint's, not the carried copy's; do not judge a carried magazine with `q_hand.lua`.)
- The whole change ran by robot (`guncheck.py ri3049 long pics mag`): out, dropped, a new one from the pouch, in, racked.
- W870, shells from the pouch (`ri3036-w870-shells-in-hand.jpg`): two shells pinched at the fingertips. Not changed.

## Tool notes

- The save list: with 2 s between 30 ms stick steps, three of three landed (with 0.4-1.2 s, one of three or four).
- `builds.py snap` with a long title failed part-way ("stopped at 585 of 649 files", path length) although it said it had
  shortened the title: a fault-list row; a short title worked.
- Not worn. Nothing here was felt by a person.
