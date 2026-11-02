// perfprobe.h -- an always-on performance recorder, one line every few seconds, one file per launch (2026-11-02).
//
// Tefa, 2026-11-02, after the third blue screen with Village running: "i have had so many times where the game becomes
// noticably unstable, stuttery and glitchy over time or when game has not been shut down for a while. might be a good
// idea to put some sort of a performance probe in the game to always record and log some data".
//
// What it records (columns in the file's header line):
//   - the game's own update rate and the present rate, with the longest gap and the count of stutters in each interval,
//   - the game process: CPU use, memory in use (working set and private), page faults, handles and threads,
//   - the graphics card's memory: what the game uses against what Windows lets it use (the budget),
//   - the whole PC's memory load and commit.
// Temperatures, power and clocks are NOT here: the LibreHardwareMonitor logger already records them every 2 s
// (claude-memory MACHINES.md), and tools/perf_read.py lays the two side by side.
//
// Built to survive what it is looking for:
//   - it runs on its OWN thread, so a stuck game still gets lines (frames = 0 while the lines keep coming means the game
//     hung; lines that just stop mean the whole PC went down),
//   - every line is forced to the disk at once (FlushFileBuffers): a blue screen loses whatever Windows had not written,
//   - one dated file per launch in reframework/data/visceral_re8/perf/, never overwritten.
// Costs: a few small system calls every PERF_PERIOD_S on a background thread; two counters per frame on the game thread.
#pragma once

namespace vn::perfprobe {

void start();     // once, from reframework_plugin_initialize (plugin.cpp): opens the file and starts the thread
void frame();     // once a game frame (UpdateBehavior, plugin.cpp)
void present();   // once per present (REFramework's on_present)

} // namespace vn::perfprobe
