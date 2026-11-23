# 2026-11-23 (evening, /lm by hand-on, PC1, Fable): the 360 view for the robot, third pass; b155 the nearest part takes the hand

Carries on from `2026-11-23c-every-gun-by-robot-hands-round-2.md` (same rig: the real headset lying on the desk, Two Frame
Sequential, VR Bench's hands, nobody wearing it; Tefa away, questions once at the end). Sheets: `2026-11-23d-sheets/`.

## The rig, what went wrong and what was added

- **The first launch came up flat**: the desk headset was not streaming (`XR_ERROR_FORM_FACTOR_UNAVAILABLE` in the loader's
  log; Virtual Desktop had no link to it), found only after a whole launch, with the options Emporium open over the title
  (closed by its own `emporium_cmd.json` `{"cmd": "close"}`; Insert alone does not close the overlay while it is up). It
  streamed again by itself two minutes later. New: `tools/sim/headset_up.py [wait s]` asks the PC's OpenXR runtime for a
  headset with no game running (UP / DOWN); `drive_real_slot.sh` asks first and launches nothing when it is down.
- **The save list's cursor**: of the six 30 ms stick steps down only 2 and then 3 landed (two launches). The slot picture
  caught it both times; the rest were stepped by hand. `[measured, n=2]` Not fixed: the route should ask the game which row
  is lit instead of counting (a tool idea in KNOWN.md).
- `turntable.py`: one row per hold (`TURN_COLS`), `TURN_STAY=1` leaves the hand on the part after the last view (pose it,
  then `snap.py`). Pictures are brightened with `SNAP_GAMMA=0.5` and cropped closer with `STAGE_BOX`.
- **`tools/sim/q_late.lua`**: how closed each hand is AS DRAWN (wrist to the middle finger's last joint, cm) at four points
  of the frame, the last after every writer. Written because one picture seemed to show the right hand flat and open while
  the left hand held a magazine: by numbers it stays a fist (11.8 cm) at every point `[measured]`; the "straight fingers"
  were the fist's first finger bones seen from outside. A picture of the gun hand from its outer side cannot tell a fist
  from a flat hand: use the numbers, or the view from the gun's left.

## b155: the nearest part takes the hand (`src/whichpart.cpp`, builds store reload/v0.1.0-b155)

- **Seen**: on the Dragoon, LG + LT aimed at the charging handle from the gun's right gave "magazine in hand": the magazine
  took the hand and LT pulled it out. `landtest.py` (new) on b154, pressing LG 30 % of the way from one part's middle toward
  the next: the F2's bolt -> magazine, its front grip -> magazine (twice), the Dragoon's charging handle -> magazine: 4 wrong
  of 10 `[measured, robot, n=1 each]`. At each part's exact middle everything passed, from three sides.
- **Why** `[inferred-static, then run]`: `reload.cpp grab_frame` gave the magazine every LG press inside its ball, unless a
  rack was due, when `rack::bolt_wants_left` gave the bolt every hand inside ITS ball (so with a rack due the F2's bolt won
  even at the magazine's middle: the evening's "2 of 3"); the front grip was not asked at all.
- **Now, one rule for every gun**: of the zones the left controller is inside (magazine, slide / bolt / pump, and on long
  guns the front grip), the one whose middle is nearest FOR ITS SIZE (distance / reach) takes the hand. A rack that is due or
  a bolt mid-cycle counts 40 % nearer (`WHICHPART_DUE_BIAS` 0.6): it still wins the overlap (Tefa 2026-11-01), not the very
  middle of the magazine. The log says so: `reload: the hand is nearer the <part> (for its size): that takes it`.
- **Run on b155** `[verified-live 2026-11-23, robot]`: every part from its own middle from three sides on the F2, Dragoon,
  SYG-12, WCX, LEMI (magazine, slide, slide from the left) and W870: all pass. The Dragoon's charging handle 30 % toward the
  magazine now gives the charging handle. Three of the 30 % presses still read "wrong" in the test and are fair calls by the
  game's own distances: the robot places the controller about 3 cm loose, and on the F2 the straight line from the bolt to
  the front grip passes the magazine. NOT run: with a rack really due (the save's F2 is empty: no shot to make one).
- The zones themselves were not moved: with the rule the Dragoon's and the SYG-12's overlaps no longer hand out the wrong
  part. Tefa can still move them in the headset with Grip Zones.

## The left hand, gun by gun (all through the Hand Poser window)

- **WCX, Dragoon, SYG-12, the charging handle (LG + LT)**: the closed hand floated palm-UP above the receiver. The docked
  wrist's first turn set to 90 (`pose.py dock.rx=90` at the "slide" spot; it rolls the hand about the forearm): the hand now
  lies over the receiver's top, fingers down its far side. Coarse; what cannot be judged from pictures: whether the fingers
  sit ON the handle or a centimetre into the dust cover. Sheets before and after.
- **WCX, Dragoon, SYG-12, the magazine**: the hand comes onto the magazine from the gun's left with the fingers round its
  front: left as it is.
- **W870, M1897, the pump**: held from below, thumb up the left side, with and without LT: left as it is. (The pump zone
  sits far up the barrel: the right-side and below pictures missed the frame; the left view was used.)
- **Handcannon (hammer, drum), Wolfsbane (hammer)**: with LG at those zones the game does not dock the wrist: the hand stays
  where the controller is and only the fingers change ("handle", "ready on drum", "ready on hammer"). So the afternoon's
  "the hammer hand hangs under the grip" was the ROBOT's controller, not Tefa's tuning: the pictures cannot judge these
  holds, and nothing was changed `[measured: the dock box answers "docked": false there; pictures]`.
- **M1911, V61, S.T.A.K.E, Samurai Edge, USM-AI** (magazine, slide over the top with LT, slide from the left with LT; three
  views each): the LEMI's poses fit; M1911 and USM-AI looked at closely, the other three at sheet size. Nothing changed.
- **The right hand**: closed on every gun pictured, with the left hand on a part too (see `q_late.lua` above). Fitting the
  one grip per handle shape was NOT done.

## b156: the GM 79's latch part turns (builds store reload/v0.1.0-b156)

- `breech.cpp lever_point`: the gun's `Lever` joint turns 28 degrees about its own y when the latch is flicked open, back
  when it shuts (0.08 s). Pictured from above `[verified-live 2026-11-23, robot, n=1]`: at rest the lever lies straight
  along the receiver; with B held the thumb lies over it; after the flick the lever stands turned to the gun's right with
  the thumb beside it. The axis and angle were a first guess that read right; Tefa may want more or less.
- **The top hold** (LG, or LG + LT, at the insert point with the latch open): not a docked hold either (the hand stays at
  the controller); its fingers were open. Given the closed grip through the window (the pose "insert point + right hand, the
  latch flicked open"). Whether the hand sits ON the barrel is the wearer's to see.

## Not done in this pass (said plainly)

- The blends between stages were not looked at again (only the LEMI's spare swap, this afternoon).
- The Samurai Edge's and USM-AI's "pulling" stage: `hold_at.py magpull30 / 60` read "magazine in hand, pull 0" on both AND
  on the LEMI, where the pull was seen working this afternoon: the probe is too slow to catch the stage, so nothing is
  learned about those two guns. The reload itself ran on b156 (the LEMI: seated -> in the grip -> in the hand).
- A long gun's magazine carried and going in, the shells in the hand, the right-hand grip fitted per gun.
- No measure for a finger passing through the gun exists yet: every "no clipping" above is by eye at sheet size.
- Nothing here was worn.
