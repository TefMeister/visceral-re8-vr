# The game's own finger movements on our hands, every gun (2026-11-04 night, Fable, home PC, OpenXR Simulator)

Steps 2 and 3 of Tefa's 2026-11-02 ask: *"default hand animations, just the hand and fingers, so wrists are not locked and
hands can still be naturally moved in vr. can you run through every default game reloading, grip and docked pose for hands
and fingers and record them somehow, so then we can use these hand grip poses when gripping weapons in VR"*. Step 1 (the
takes, all 16 guns + the knife) was done 2026-11-02; the W870's shell-in was the one clip playing (b057).

## What the takes say (read before cutting) `[measured 2026-11-04 from the 2026-11-02 takes]`

- Every reload plays on the player's motion layer 1 as a chain of motion ids: idle 2420 → 2511 (reach for a shell / open the
  cover) → 2512 x N (one round in, the frame counter restarting per round) → 2513 (the pump / the cover closed) → 2100 → 2106
  → 2420 on the round-by-round guns (W870, M1897, Rocket Pistol, Wolfsbane, Handcannon); 2420 → 2500 (the whole magazine
  change) → 2100 → 2106 → 2420 on the magazine guns and the GM 79. The V61's take goes 2100 → 2500 → 2422 (an empty-gun idle).
- Which hand does it, by how far the finger joints turn: the LEFT hand on the shotguns, the Rocket Pistol and every magazine
  gun; the RIGHT hand pushes the rounds in on the Wolfsbane and the Handcannon (right finger curl 72-97 deg while the left
  stays at 52-59); the right hand also works the F2 Rifle's bolt inside its 2500 (right 17-80 deg, before and after the
  magazine) and tightens its grip at the start of every pistol reload (29 → 50 deg).
- A magazine change has one shape on every magazine gun: the left hand opens (reaching), closes fully on the magazine
  (65-73 deg), opens again (15-22 deg: the magazine let go / the new one taken), half-closes on the new magazine, and ends
  at the idle curl. The split between "out" and "in" = the bottom of the first opening after the first full grasp.
  The F2 Rifle breaks the rule (the fore-end hold curls more than the magazine grasp, and the bolt comes first), so it is
  written whole, uncut.

## What was built

- `dev-archive/native/tools/make_finger_book.py`: cuts every take into `reframework/data/visceral_re8/clips/<gun>_<event>.csv`
  with the joints of the hand(s) that move in that part (a joint turning 10 deg or more): `round_in` (the second 2512
  cycle), `rack` (2513), `mag_out` / `mag_in` (2500 split as above), `reload` (whole 2500: the GM 79, the F2). 30 clips for
  16 guns. The clips are the game's animation data: on the PC only.
- `src/shellclip.cpp` (was the W870-only player): a clip's header names its joints, so one clip drives the left hand, the
  right, or both; one play per hand at a time, a new clip on a hand replaces the old; `play(gun, event)`; blended in from
  the pose found, out to it again, written after every other finger writer at both render points. `playing_left()` is what
  fingers.cpp and righthand.cpp stand aside for (a right-hand clip no longer stops the left hand's opener).
- Wired: `round_in` at every round-in (reload.cpp insert_round, which the Wolfsbane's gate, the revolver drum and the shell
  port all go through); `mag_out` when the magazine comes out (pull_out: LT on a long gun, right B on a pistol); `mag_in`
  when a new magazine goes home (fill_magazine). `rack` and `reload` are cut but not played yet (see Open).
- Test without a headset: `clips/play.txt` takes "<gun> [event]".

## Open

- The Handcannon: the game loads it with the RIGHT hand; our breech code loads it with the LEFT, so its round_in clip (right
  joints) plays on the hand holding the grip. Mirroring a right-hand clip onto the left needs the finger bones' mirror rule
  (untested); until then the Handcannon's round-in fingers are the game's recorded right hand, which may look wrong.
- `rack` (the pump's 2513, 1-1.3 s): when to start it. rack.cpp's "hand on the pump" is the moment; cycle-complete is too
  late. Not wired tonight.
- The F2 Rifle: cut its 2500 by hand into bolt-open (right), mag_out, mag_in, bolt-close (right) once seen.
