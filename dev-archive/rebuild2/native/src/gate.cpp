// gate.cpp -- see gate.h
#include "gate.h"

#include "base.h"
#include "ready.h"

#include <utility>
#include <vector>

namespace vr8::gate {

namespace {
constexpr float REPORT_EVERY_S = 60.0f;
constexpr size_t MAX_WAITING = 32;          // more than this waiting is a part gone wrong: the rest is dropped

const char* const KIND_NAME[(int)Kind::Count] = {"door-open", "door-solid"};

struct Waiting {
    Kind kind;
    std::function<void()> request;
};
std::vector<Waiting> g_waiting;
unsigned g_made[(int)Kind::Count]{}, g_dropped[(int)Kind::Count]{};
float g_last_report = 0.0f;
} // namespace

void ask(Kind kind, std::function<void()> request) {
    if (g_waiting.size() >= MAX_WAITING) { ++g_dropped[(int)kind]; return; }
    g_waiting.push_back({kind, std::move(request)});
}

void run() {
    std::vector<Waiting> now;
    now.swap(g_waiting);                    // a request that asks again is made next frame, not in this pass
    const bool player_here = ready::now().player != nullptr;
    for (auto& w : now) {
        if (!player_here) { ++g_dropped[(int)w.kind]; continue; }
        w.request();
        ++g_made[(int)w.kind];
    }
    const float t = now_s();
    if (t - g_last_report < REPORT_EVERY_S) return;
    g_last_report = t;
    for (int k = 0; k < (int)Kind::Count; ++k) {
        if (g_made[k] == 0 && g_dropped[k] == 0) continue;
        LOGI("%s request gate: %s: %u made, %u dropped in the last minute", TAG, KIND_NAME[k], g_made[k], g_dropped[k]);
        g_made[k] = g_dropped[k] = 0;
    }
}

} // namespace vr8::gate
