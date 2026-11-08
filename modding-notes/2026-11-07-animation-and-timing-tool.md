# Animation & Timing: the window that tunes a moving hand, and the timings table (2026-11-07 06:30 - 09:10)

Dev PC, Fable, no game running. Tefa's morning ask: *"a tool that lets me go through any of the player body's
animations ... adding or removing frames ... tune the weapons timings, like you did with the bullet cover yesterday ...
fine tune that original hand movement and placement frame by frame"*. First target: *"the left hand rotating the drum,
right now it clips through the drum a lot"*, then *"it sits through the drum"*: the whole hand is placed wrong for the
whole turn, not one finger on one frame. Built on the dev PC, to be run at home. Tefa: *"please build the best you can
with info you got, and lets fine tune the tool later"*.

The window lives in its own repo, `animation-timing-vr` (private until Tefa says otherwise; design in its
`docs/superpowers/specs/2026-11-07-animation-timing-vr-design.md`). This note is the plugin's half.

## What changed in the plugin (b080 when the home PC builds it; dll bbc1123f, 674,304 bytes, both exports)

- **`timings.h` / `timings.cpp` (new): the mod's named seconds are a live table.** Twenty numbers that were constants
  in `settings.h` (the cover swing, the thumb lift, the hammer press and its depth, the drum turn, the glides, the
  hand-over, the flick, the clip blend, the case and round travel, the held follow, the load ease) are read through
  `timings::v(key)`. `reframework/data/visceral_re8/timings.json` (`{key: value}`) overrides any of them; it is re-read
  within half a second of a change. The plugin writes `timings_known.json` (every key with its default, unit, words and
  the value in force) for the window. `gate.cpp` (27 places), `drumrounds.cpp` (3), `breech.cpp` (2) read the table;
  the cover's swing uses the table when the key is set, else the `lid_swing.json` seconds as before.
- **`shellclip.cpp` rewritten around an edited frame list.** A clip is its raw CSV rows plus `<gun>_<event>.edit.json`:
  `ops` (`remove i`, `hold i n`, `speed from to x`, applied in order to the frame list, every CSV row once first) and
  `nudges` (keys by SOURCE row: per-joint turns in degrees and a six-number whole-hand move, x y z cm and rx ry rz deg,
  in the gun's axes). Keys interpolate along the edited time between keyed frames and sit flat outside; a key survives
  frames added or removed around it. The file is re-read within a quarter second. `scrub.json` from the window holds an
  edited frame on the hand (`hold true, frame k`; another seq moves the held frame), lets it go (blends out over the
  clip blend) or plays the clip once (`frame -1`). `clips_state.json` twice a second: the gun's clips (event, hands,
  frame counts, seconds, joints, raw times, the edited `src` and `t` lists) and what plays (hand, frame, held, blend).
  Bridge slot 186 still says a clip is playing.
- **`dockpose.cpp`: the whole-hand move.** `shellclip::hand_nudge(left, out[6])` gives the hand's move at the clip's
  current frame; dockpose adds it to the dock pose's easing and applies it in the gun's axes, the last writer on the IK
  target as before. With no gun rotation from gate / rack / zones it takes the weapon transform's. This is the path that
  fixes the drum hand: hold the turn on a frame, drag the hand off the drum, key it, step on.

## Not yet done, for the home PC

`[compile-verified 2026-11-07]` only. The window was checked against a stand-in game (its `test/fake_game.py`) and its
self-test; no game has run with any of it. First run: build b080 (`build.sh --deploy`), start the game and the window,
put the script in, take the Wolfsbane, pick the drum turn's clip, HOLD A FRAME, step to where the hand sits in the drum,
drag the WHOLE HAND sliders until it sits on it, step on, let go, turn the drum for real. Then: does the mod re-read the
edit while the hand is held (it should, within a quarter second); does the timings slider move the cover's swing live.

## Dead ends and cautions

- The plugin side reads `timings.json` on its modification time, checked twice a second; a write that keeps the time
  (none known) would be missed.
- The 20 timing defaults are the `settings.h` constants, so nothing changes until a key is set; `timings.json` absent
  = exactly b079's behaviour.

## 2026-11-08 (home PC, Opus): the drum follows the hand clip, frame by frame

Tefa: *"rotating the drum is what i needed this app for, but it's only half of the solution if the drum doesn't travel
frame by frame as well after i press LT when the bullet guard is open"*. Before this, LT started two separate things: the
left half of `round_in` on the hand, and the drum's turn on its own clock (`CYL_TURN_S`, 0.40 s). A frame held in the
window froze the hand while the drum finished by itself, and SLOWER / ADD ONE HERE never reached the drum `[inferred-static]`.

Now (`shellclip` `declare_part` / `part` / `part_at`, `gate.cpp` `turn_drum`): while LT's `round_in` plays (tagged
"drum"; RT's own `round_in` from `reload.cpp` is not) or the window holds a frame of it, the drum stands where the clip's
edited time says: 0 = where this turn started, 1 = one chamber on, straight along the edited time unless keyed
(`"parts":{"drum":u}` on a nudge key in the edit file; 0 / 1 anchor the first / last frame where they carry no key). No
play = the old clock finishes the turn. The window shows a DRUM slider on that clip (`clips_state.json` `"parts"`).
Same rule as the window's `ClipMath.PartAt` (7 self-test checks there). Compiled, dll `353ddf59` `[compile-verified]`;
not run in the game yet. To check in the drum-hand run: hold frames of the drum turn, the drum should stand part way.
