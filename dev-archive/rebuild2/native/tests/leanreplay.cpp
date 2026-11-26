// leanreplay.cpp -- rebuild 2 (2026-11-26, RE8-092): the lean fix's SHIPPED sums (src/leanmath.h, compiled in, not a
// copy) run with no game, two ways:
//
//   leanreplay.exe selftest         made-up necks with a known answer (a stand, a walk, a stop that leans 12 cm, a
//                                   head that nods): the fix must take the lean out and leave the rest alone
//   leanreplay.exe <kept log>       the "lean:" lines leanrec wrote in play. Each line is HALF A SECOND boiled down
//                                   to the neck's nearest and furthest distance behind the eyes, the speed and the
//                                   loader's cutscene flag: NOT a frame-by-frame recording. So each window is
//                                   rebuilt as a path (below) and the sums run over it at 90 pictures a second.
//                                   What comes out is "what the neck would have read with the fix moving the body",
//                                   under the one assumption the walk file must still prove: moving the body's
//                                   place by x moves the neck by x on the next picture.
//
// The path a window is rebuilt as: a window that is a stop (the cutscene flag up, or standing right after one) goes
// from its furthest to its nearest in the first 40% and back in the rest (the measured shape: in fast, out slow);
// any other window swings once between its two ends.
#define _CRT_SECURE_NO_WARNINGS
#include "leanmath.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

using namespace vr8;

namespace {
constexpr float DT = 1.0f / 90.0f;
constexpr int WINDOW_FRAMES = 45;

struct Window { float speed, lo, hi; bool flag; };

struct Run {
    leanmath::State state;
    leanmath::Numbers numbers;
    float applied = 0.0f;            // what the body was moved by for the picture now measured (one picture late)
    float seen_lo = 1e9f;            // the nearest the neck came to the eyes WITH the fix
    float raw_lo = 1e9f;             // ... and without
    float ask_hi = 0.0f;
    // one picture: `lean_free` is where the neck would be with nothing of ours moving the body
    float picture(float lean_free, float speed, bool in_play = true, float down = 0.0f) {
        const float seen = lean_free + applied;                 // THE ASSUMPTION: the move shows whole, a picture later
        const float ask = leanmath::step(state, numbers, seen, applied, down, speed, in_play, DT);
        seen_lo = std::fmin(seen_lo, seen);
        raw_lo = std::fmin(raw_lo, lean_free);
        ask_hi = std::fmax(ask_hi, ask);
        applied = ask;
        return seen;
    }
    void fresh() { seen_lo = raw_lo = 1e9f; ask_hi = 0.0f; }
};

int g_bad = 0;
void check(const char* what, bool ok, float got) {
    std::printf("%s %s (%.1f cm)\n", ok ? "ok  " : "FAIL", what, got * 100.0f);
    if (!ok) ++g_bad;
}

int selftest() {
    Run r;
    // 2 s standing at 16 cm with a 1 cm sway: the standing distance is learned, nothing is asked
    for (int i = 0; i < 180; ++i) r.picture(0.16f + 0.005f * std::sin(i * 0.05f), 0.0f);
    check("standing: learned near 16 cm", r.state.learned && std::fabs(r.state.standing_m - 0.16f) < 0.012f, r.state.standing_m);
    check("standing: nothing asked", r.ask_hi < 0.002f, r.ask_hi);
    // 3 s walking, the neck between 11 and 18 cm (as measured): next to nothing asked
    r.fresh();
    for (int i = 0; i < 270; ++i) r.picture(0.145f + 0.035f * std::sin(i * 0.2f), 2.0f);
    check("walking: at most 2 cm asked", r.ask_hi < 0.02f, r.ask_hi);
    // a stop: 16 -> 4 cm in 0.2 s, back to 16 over 0.5 s (a 12 cm lean)
    r.fresh();
    for (int i = 0; i < 18; ++i) r.picture(0.16f - 0.12f * (i + 1) / 18.0f, 0.5f);
    for (int i = 0; i < 45; ++i) r.picture(0.04f + 0.12f * (i + 1) / 45.0f, 0.0f);
    check("a stop: without the fix the neck came to 4 cm", std::fabs(r.raw_lo - 0.04f) < 0.002f, r.raw_lo);
    check("a stop: with it, never nearer than 9 cm", r.seen_lo > 0.09f, r.seen_lo);
    for (int i = 0; i < 180; ++i) r.picture(0.16f, 0.0f);
    check("after the stop: let go again", r.state.ask_m < 0.002f, r.state.ask_m);
    check("after the stop: the standing distance was not dragged down", std::fabs(r.state.standing_m - 0.16f) < 0.015f, r.state.standing_m);
    // a swing BACK (the jump down, the vault's second half): 16 -> 30 cm in 0.2 s, held: the ask goes negative, by
    // the swing less the dead band, and is let go again
    r.fresh();
    for (int i = 0; i < 18; ++i) r.picture(0.16f + 0.14f * (i + 1) / 18.0f, 0.5f);
    for (int i = 0; i < 27; ++i) r.picture(0.30f, 0.5f);
    check("a swing back: the body is asked forward by about 10 cm", r.state.ask_m < -0.09f && r.state.ask_m > -0.11f, r.state.ask_m);
    for (int i = 0; i < 180; ++i) r.picture(0.16f, 0.0f);
    check("after the swing back: let go again", std::fabs(r.state.ask_m) < 0.002f, r.state.ask_m);
    // looking down: the loader moves the body back 10 cm at straight down; that is not a lean and not a standing change
    r.fresh();
    for (int i = 0; i < 180; ++i) r.picture(0.16f + 0.10f * 0.7f, 0.0f, true, 0.7f);
    check("looking down: nothing asked", r.ask_hi < 0.002f, r.ask_hi);
    check("looking down: the standing distance kept", std::fabs(r.state.standing_m - 0.16f) < 0.015f, r.state.standing_m);
    // a real scene: nothing asked, at once
    r.fresh();
    r.picture(0.02f, 0.0f, false);
    check("a real scene: nothing asked", r.state.ask_m == 0.0f, r.state.ask_m);
    // a teleport reading
    r.picture(150.0f, 0.0f);
    check("a teleport reading: nothing asked", r.state.ask_m == 0.0f, r.state.ask_m);
    // nothing before the standing distance is learned
    Run cold;
    for (int i = 0; i < 30; ++i) cold.picture(0.03f, 1.0f);
    check("before anything is learned: nothing asked", cold.ask_hi == 0.0f, cold.ask_hi);
    std::printf(g_bad == 0 ? "leanreplay selftest: all right\n" : "leanreplay selftest: %d FAILED\n", g_bad);
    return g_bad == 0 ? 0 : 1;
}

bool parse(const std::string& line, Window& w) {
    const size_t at = line.find(" lean: ");
    const size_t neck = line.find("neck ", at == std::string::npos ? 0 : at);
    if (at == std::string::npos || neck == std::string::npos) return false;
    float lo = 0, hi = 0;
    if (std::sscanf(line.c_str() + at + 7, "%f", &w.speed) != 1) return false;
    int lo_cm = 0, hi_cm = 0;                       // whole centimetres ("14..19"; "%f" would eat the first dot)
    if (std::sscanf(line.c_str() + neck + 5, "%d..%d", &lo_cm, &hi_cm) != 2) return false;
    lo = (float)lo_cm;
    hi = (float)hi_cm;
    w.lo = lo * 0.01f;
    w.hi = hi * 0.01f;
    w.flag = line.find("CUTSCENE", at) != std::string::npos;
    return true;
}

int replay(const char* path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) { std::printf("cannot read %s\n", path); return 2; }
    std::vector<Window> windows;
    std::string line;
    int skipped = 0;
    while (std::getline(f, line)) {
        Window w{};
        if (!parse(line, w)) continue;
        // a window that holds a load, a teleport or a real scene's jump (the neck further than 40 cm either way)
        if (w.hi > 0.40f || w.lo < -0.40f || w.speed > 8.0f) { ++skipped; continue; }
        windows.push_back(w);
    }
    std::printf("%zu half-second windows read (%d more left out: a load, a teleport or a scene's own jump)\n", windows.size(), skipped);
    if (windows.empty()) return 2;
    Run r;
    // the standing distance. leanrec wrote no line for a window in which nothing moved, so plain standing is not in
    // the log; what is: where the neck SETTLED after each stop (the far end of the slow windows with the flag down).
    // Their middle one is taken, and the sums learn it the way play would (a second of standing there).
    std::vector<float> settled;
    for (const auto& w : windows) if (!w.flag && w.speed < 0.5f) settled.push_back(w.hi);
    if (settled.empty()) { std::printf("no settled window to take the standing distance from\n"); return 2; }
    std::sort(settled.begin(), settled.end());
    for (int i = 0; i < 90; ++i) r.picture(settled[settled.size() / 2], 0.0f);
    std::printf("standing distance taken as %.0f cm\n\n", r.state.standing_m * 100.0f);
    std::printf("   window                    neck nearest, cm      most asked\n");
    std::printf("   speed   kind              recorded   with fix   cm\n");
    int stops = 0, stops_better = 0, others = 0, others_touched = 0;
    float worst_before = 1e9f, worst_after = 1e9f;
    bool after_flag = false;
    for (const auto& w : windows) {
        const bool stop = w.flag || (after_flag && w.speed < 0.5f && w.hi - w.lo > 0.06f);
        after_flag = w.flag;
        r.fresh();
        for (int i = 0; i < WINDOW_FRAMES; ++i) {
            const float t = (i + 0.5f) / WINDOW_FRAMES;
            float neck;
            if (stop) neck = t < 0.4f ? w.hi + (w.lo - w.hi) * (t / 0.4f) : w.lo + (w.hi - w.lo) * ((t - 0.4f) / 0.6f);
            else neck = (w.lo + w.hi) * 0.5f + (w.hi - w.lo) * 0.5f * std::cos(t * 6.2831853f);
            r.picture(neck, stop ? w.speed * (1.0f - t) : w.speed);
        }
        if (stop) {
            ++stops;
            if (r.seen_lo > r.raw_lo + 0.02f || r.raw_lo > r.state.standing_m - r.numbers.dead_m) ++stops_better;
            worst_before = std::fmin(worst_before, r.raw_lo);
            worst_after = std::fmin(worst_after, r.seen_lo);
            if (stops <= 24)
                std::printf("   %4.1f    stop%s   %6.0f     %6.0f     %4.0f\n", w.speed, w.flag ? " (flag up)  " : " (settling) ",
                            r.raw_lo * 100.0f, r.seen_lo * 100.0f, r.ask_hi * 100.0f);
        } else {
            ++others;
            if (r.ask_hi > 0.02f) ++others_touched;
        }
    }
    std::printf("\n%d stop windows: the neck's nearest to the eyes was %.0f cm as recorded, %.0f cm with the fix; %d of %d better or already fine\n",
                stops, worst_before * 100.0f, worst_after * 100.0f, stops_better, stops);
    std::printf("%d other windows (standing, walking): the fix asked for more than 2 cm in %d of them\n", others, others_touched);
    return 0;
}
} // namespace

int main(int argc, char** argv) {
    if (argc < 2) { std::printf("usage: leanreplay selftest | <kept log with lean: lines>\n"); return 2; }
    if (std::strcmp(argv[1], "selftest") == 0) return selftest();
    return replay(argv[1]);
}
