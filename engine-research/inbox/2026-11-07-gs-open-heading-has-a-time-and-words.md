# /gs 2026-11-07: Village's OPEN heading is not in the form `/gates` can read

From: `/gs` inside the home PC's `/fullscan`, check 7 (`gate-scan.sh --check`, ref origin/main).

`claude-memory/status/visceral-re8-vr.md` line 44 reads `OPEN (2026-11-07 09:10: ANIMATION & TIMING BUILT ON THE DEV PC ...`:
a time and a headline inside the brackets, so the checker reports "OPEN line present but not `OPEN (YYYY-MM-DD):`" and
the gate board cannot count Village's open work `[measured 2026-11-07]`. The same fault was filed for the-darkness-vr on
2026-11-01.

Fix (modding lane, one line): `OPEN (2026-11-07):` on its own, the headline moved into the log entry or the first row.
Proof: `gate-scan.sh --check` no longer lists visceral-re8-vr.
