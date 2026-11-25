# /gs 2026-11-25: the heap-lock topic's link to tonight's freeze is weaker than it reads

Supersedes: external-research/topics/2026-11-25-kananlib-heap-lock-fix-startup-hang.md, section "Why it matters here"

The topic says what was seen "matches" the heap-lock deadlock. Measured since: both freeze logs have every frozen thread
resumed (81 suspends, 81 resumes, the last 10+ s before the freeze), unlike REFramework's own recorded start-up
deadlock (routes/resident-evil-village/KNOWN.md, 2026-11-23: 62 suspends against 17 resumes). Suggest the topic's tag
on that link goes from a suspect to "not supported by tonight's logs" and its INDEX row says so; the upstream facts
(the fix, our build predating it) stay. Detail: the engine-research inbox drop of the same date.
