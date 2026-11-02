# An always-on performance probe: why the game gets stuttery and glitchy the longer it runs

Order: 4045
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-11-02

`[raw]` · `[looks doable]` — *judged from the mod's own log only; not built or tried*

> "i have had so many times where the game becomes noticably unstable, stuttery and glitchy over time or when game has
> not been shut down for a while. might be a good idea to put some sort of a performance probe in the game to always
> record and log some data" — 2026-11-02

A quiet recorder that runs every time the game runs and writes a line every few seconds: frame times, how much memory the
game and the graphics card are using, CPU and graphics-card load and temperature, and what the mod itself is doing (scope
drawing, hands, reloads). Kept per run instead of being overwritten at the next launch, so a long session that went bad
can be read afterwards and the slow climb (memory filling up, something piling up, heat) shows as a trend.

Asked on the day of the third blue screen with Village running (2026-11-02; the earlier two were 2026-09-13 and
2026-10-02). Tefa: it may not be tied to the blue screens, but the same log would show what the PC was doing in the
minutes before one.

🟡 **Partly there already:** the mod writes the frame rate and frame times once a second, but only into the game's own
log, which the next launch wipes, and with no memory, load or temperature numbers.

**What it'd take:** the memory and frame numbers from inside the mod (cheap, one line every few seconds); the load and
temperature numbers from a small helper outside the game; a folder that keeps one log per run; and a short reader that
draws the trend so nobody has to read raw numbers.

Verbatim record: [`inbox/2026-11-02-village-performance-probe.md`](../inbox/2026-11-02-village-performance-probe.md)

---

_Other categories appear as they arrive — gameplay, visuals, audio, level design, UI, controls, enemies._ Nothing is missing; none of them have been needed yet._

**To add one:** `[village] your idea` — anywhere, any time.
🔗 Ideas for **all four** Resident Evil games at once: [`resident-evil-all.md`](resident-evil-all.md).
