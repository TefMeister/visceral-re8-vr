# A thread-freezing deadlock fixed in REFramework's helper library (2026-11-17), not in our build

**For:** the b164 freeze of 2026-11-25 (the game stops drawing and sits idle; see the FAULTS.md row of that date and
the Gold Digger note `engine-research/inbox/2026-11-25-gd-b164-freeze-and-shelves.md`).

## What it is

REFramework freezes every other game thread for a moment whenever it installs a hook (its helper library, kananlib,
`suspend_threads` / `WorldLock`). On 2026-11-17 kananlib's commit `114de171` "Thread: Fix heap lock oversight" added
the **process heap lock** to the locks that must not be held by a frozen thread. Its own comment describes the fault
[reported 2026-11-25]:

> a thread suspended inside RtlAllocateHeap/RtlFreeHeap while owning the heap's critical section deadlocks the next
> allocation ... (Seen as an intermittent REFramework startup hang in a game that was loading, i.e. allocating hard,
> while the world was frozen.)

REFramework took it the same day ("Deps: Update kananlib (fix startup deadlock when freezing threads)", nightly
01441, 2026-11-17).

## Why it matters here

- Our REFramework is the `pd-upscaler` build, commit `76298bd` (2026-03-11) [measured: the Village log's "Commit
  hash" line, 2026-11-25]. It is 90 commits behind master and older than the fix, so this deadlock can happen in it.
- What it looks like matches what was seen: a hang with the game idle (almost no CPU), not a busy loop
  [measured 2026-11-25]. In the 02:43 run REFramework was still adding hooks at 02:43:54 and 02:43:55
  (`set_equipWeaponRight`, `get_PrimaryCamera`) while the game loaded, and the frames stopped at about 02:43:58
  [measured, the run's log and perf csv].
- What does NOT fit: the 02:35 run froze 40 s into play, right after the rifle was drawn, with no hook line logged
  near it. A hook installed by our own native plugin (safetyhook freezes threads its own way) or one that logs
  nothing would still fit; that is not checked. [hypothesis]
- b162 ran 36 min clean the same night, b164 froze twice in two runs. An intermittent deadlock can still look like
  "this build", so the b162 run tomorrow does not rule this out unless b162 is run more than once.

## Next step it unlocks

1. Tomorrow's b162 test: if b162 also freezes, this becomes the first suspect.
2. Either way, a cheap test: a REFramework build that has the fix (nightly 01441 or later), on a copy, checked
   against what our mod needs from `pd-upscaler` (the TemporalUpscaler / DLSS part). That is the tool check's (/gu)
   question, not research's.
3. The same old build runs in RE2 (`76298bd`, measured from its log 2026-11-23), so RE2 can hit the same hang.

## Sources

- cursey, kananlib commit 114de171 "Thread: Fix heap lock oversight" (2026-11-17) — https://github.com/cursey/kananlib/commit/114de171
- praydog, REFramework commit "Deps: Update kananlib (fix startup deadlock when freezing threads)" (2026-11-17) and
  nightly 01441 — https://github.com/praydog/REFramework and https://github.com/praydog/REFramework-nightly/releases

## Since then (/gs correction, 2026-11-25, folded in 2026-11-28)

- The link to the b164 freeze is **not supported by the freeze logs** `[measured 2026-11-25]`: both freeze logs show
  every frozen thread resumed (81 suspends, 81 resumes, the last more than 10 s before the freeze). REFramework's own
  recorded start-up deadlock looks different (routes/resident-evil-village/KNOWN.md, 2026-11-23: 62 suspends against
  17 resumes). The upstream facts stand: kananlib fixed the deadlock on 11-17, and our `76298bd` build predates the fix.
  The suspect line above is withdrawn as an explanation of the b164 freeze.
