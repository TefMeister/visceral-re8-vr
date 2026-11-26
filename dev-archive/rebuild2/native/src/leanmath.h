// leanmath.h -- rebuild 2 (2026-11-26, RE8-092): the lean fix's sums, with nothing of the game in them, so the
// SHIPPED sums can be run over recorded numbers with no game (native/tests/leanreplay.cpp) before anyone wears it.
//
// The fault (Tefa, 2026-11-26): "when i run and stop, Ethan's whole body get's pushed forward so for less than a
// second i'm looking through his body"; after b186 and a follow lag of 0.05 s: "still jumps ahead". Measured where
// the body is drawn (leanrec, PrepareRendering post, n=3 stops and the kept log of 18:23): standing, the neck is
// 14 to 19 cm behind the eyes; in the stop motion it dips to 4 to 6 cm while the hip stays at 10 to 14: the upper
// body's own lean in that motion, about 12 cm. Walking it stays at 11 to 18.
//
// The sum: the neck's distance behind the eyes, with what we already moved the body by taken out again (so the sum
// never chases its own tail) and the loader's own look-down shift taken out, is compared with what it is while the
// player STANDS (learned in play, never assumed: two designs that assumed it were wrong, bridge script, b183 and
// b184). Whatever a motion takes it below that, past a dead band, is what the body should sit further back by.
// Out quickly, back slowly. Nothing before the standing distance is learned; never more than MAX_M.
#pragma once

#include <algorithm>
#include <cmath>

namespace vr8::leanmath {

struct Numbers {
    float dead_m = 0.04f;        // the standing distance moves this much with the head alone (measured 14..19 cm)
    float max_m = 0.20f;         // never ask for more
    float out_s = 0.05f;         // how fast the ask grows (a stop leans in about a quarter second)
    float back_s = 0.30f;        // how fast it is let go again
    float still_mps = 0.05f;     // slower than this is standing
    float learn_s = 0.6f;        // standing this long, the distance steady: it is the standing distance
    float steady_m = 0.02f;      // "steady": it moved less than this over learn_s
    float adapt = 0.02f;         // per frame, once learned: the standing distance follows slowly
    float lookdown = 0.10f;      // the loader's own shift when the view looks down, metres at straight down [read, RE8VR.cpp]
    float jump_m = 1.0f;         // a reading this far out is a load or a teleport, not a lean
};

struct State {
    bool learned = false;
    float standing_m = 0.0f;     // the neck's distance behind the eyes while standing, shifts taken out
    float still_s = 0.0f;
    float still_lo = 0.0f, still_hi = 0.0f;
    float ask_m = 0.0f;          // what the body should sit further back by, now
    float raw_m = 0.0f;          // the last reading with the shifts taken out (for the recorder)
};

// One picture. behind_m: the neck behind the eyes, level, as drawn. applied_m: how far back the body was already
// moved for this picture. down: how far the view looks down, 0 level .. 1 straight down. in_play: no real scene,
// the headset in use. Returns the ask (State::ask_m).
inline float step(State& s, const Numbers& n, float behind_m, float applied_m, float down, float speed_mps,
                  bool in_play, float dt) {
    if (!in_play || !std::isfinite(behind_m) || std::fabs(behind_m) > n.jump_m) {
        s.ask_m = 0.0f;
        s.still_s = 0.0f;
        return 0.0f;
    }
    const float raw = behind_m - applied_m - n.lookdown * down;
    s.raw_m = raw;
    // learning: only while standing, with nothing asked, and only a reading that holds still
    if (speed_mps < n.still_mps && s.ask_m < 0.005f) {
        if (s.still_s <= 0.0f) s.still_lo = s.still_hi = raw;
        s.still_lo = std::min(s.still_lo, raw);
        s.still_hi = std::max(s.still_hi, raw);
        if (s.still_hi - s.still_lo > n.steady_m) {
            s.still_s = 0.0f;                          // still settling after a stop: start the wait again
        } else {
            s.still_s += dt;
            if (s.still_s >= n.learn_s) {
                if (!s.learned) { s.learned = true; s.standing_m = raw; }
                else s.standing_m += (raw - s.standing_m) * n.adapt;
            }
        }
    } else {
        s.still_s = 0.0f;
    }
    const float want = s.learned ? std::clamp(s.standing_m - n.dead_m - raw, 0.0f, n.max_m) : 0.0f;
    const float tau = want > s.ask_m ? n.out_s : n.back_s;
    s.ask_m += (want - s.ask_m) * (1.0f - std::exp(-dt / tau));
    if (s.ask_m < 0.0005f && want <= 0.0f) s.ask_m = 0.0f;
    return s.ask_m;
}

} // namespace vr8::leanmath
