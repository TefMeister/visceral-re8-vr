# /gr 2026-11-25: a REFramework startup deadlock fixed upstream on 11-17, not in our build

For the b164 freeze (FAULTS.md, 2026-11-25). kananlib (REFramework's helper library) fixed a deadlock on 2026-11-17:
a game thread frozen while it holds the process heap lock hangs the next allocation, "seen as an intermittent
REFramework startup hang in a game that was loading". Our REFramework is `pd-upscaler` commit `76298bd`
(2026-03-11), older than the fix. The 02:43 freeze came 2-3 s after REFramework's last hook installs; the 02:35
freeze had no hook line near it, so this is a suspect, not the answer. [hypothesis]

Topic: `external-research/topics/2026-11-25-kananlib-heap-lock-fix-startup-hang.md`.

Suggested dossier line (dead ends / open questions): "A hang with the game idle can be REFramework's own thread
freezing (kananlib heap-lock deadlock, fixed upstream 2026-11-17, nightly 01441); our `pd-upscaler` build lacks the
fix." Suggested test: run b162 more than once; if any run freezes, try a REFramework build with the fix on a copy.
