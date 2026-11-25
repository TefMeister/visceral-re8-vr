# /gs 2026-11-25: tonight's two freezes are NOT REFramework's start-up thread-freeze deadlock

Supersedes: engine-research/inbox/2026-11-25-gr-heap-lock-hang.md (its "a suspect" weight only; the facts in it stand)

The routes repo already records REFramework's own start-up deadlock (ai-game-control-profiles,
`routes/resident-evil-village/KNOWN.md`, "2026-11-23 (afternoon)"): the log stops on `[Thread.cpp:42] Suspending <id>`
lines with far fewer `Resuming` lines (62 against 17), before `textures have been setup`.

Tonight's two b164 freezes do not have that sign `[measured 2026-11-25]`: `Suspending` 81 and `Resuming` 81 in both
(`re2_framework_log.2026-11-25-freeze-b164.txt`, `...-freeze2-b164-after-restart.txt` beside the game), the same as the
good b161 run, and the last of them at 02:34:39 and 02:43:45, well before the frames stopped (02:35:23, 02:43:58). The
hook installs at 02:43:54-55 left no suspend lines at all. So the kananlib heap-lock deadlock (fixed 2026-11-17) stays
a known REFramework hazard but has no evidence behind it for tonight's freezes; the b163 / b164 changes (and the newer
`hand_poser.lua` that came in with them, 02:26) are the first suspects again. `[inferred-static]`

Tomorrow's test is unchanged: b162 put back; it runs = the cause is in b163 / b164 / that `hand_poser.lua`.
