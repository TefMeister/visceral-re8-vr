// spinestill.cpp -- see spinestill.h
#include "spinestill.h"

#include "base.h"
#include "bodyturn.h"
#include "bridge.h"
#include "jointwriter.h"
#include "ready.h"

namespace vr8::spinestill {

namespace {
// ---- the named numbers ------------------------------------------------------------------------------------------
constexpr float TWIST_SHARE = 0.5f;         // the lower spine turns by this much of the head's angle off the body
                                            // [measured 2026-11-26, spinestill.h]
constexpr float SMALL_RAD = 0.003f;         // under this (about 0.2 degrees) nothing is asked

MO* g_lower = nullptr;                      // Spine_0: turned toward the view
MO* g_upper = nullptr;                      // Spine_1: turned back by the same amount
bool g_looked = false, g_missing_told = false;
unsigned g_generation = 0;

Quat mul(const Quat& a, const Quat& b) {
    return {a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y, a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w, a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z};
}
Quat about_up(float angle) { return {0.0f, std::sin(angle * 0.5f), 0.0f, std::cos(angle * 0.5f)}; }
} // namespace

void pose() {
    const auto& player = ready::now();
    if (player.generation != g_generation) {
        g_generation = player.generation;
        g_lower = g_upper = nullptr;
        g_looked = false;
    }
    if (player.transform == nullptr || bridge::flag(bridge::S_CUTSCENE)) return;
    const float off = bodyturn::head_off();
    if (std::fabs(off) < SMALL_RAD) return;
    if (!g_looked) {
        g_looked = true;
        g_lower = jointwriter::joint_by_name(player.transform, L"Spine_0");
        g_upper = jointwriter::joint_by_name(player.transform, L"Spine_1");
        if ((g_lower == nullptr || g_upper == nullptr) && !g_missing_told) {
            g_missing_told = true;
            LOGW("%s spine: Spine_0 or Spine_1 was not found; the spine is left to the game", TAG);
        }
    }
    if (g_lower == nullptr || g_upper == nullptr) return;
    Quat lower{}, upper{};
    if (!jointwriter::read_local_rotation(g_lower, lower) || !jointwriter::read_local_rotation(g_upper, upper)) return;
    const float share = TWIST_SHARE * off;
    jointwriter::ask_local_rotation(jointwriter::Owner::SpineStill, g_lower, mul(about_up(-share), lower));
    jointwriter::ask_local_rotation(jointwriter::Owner::SpineStill, g_upper, mul(about_up(share), upper));
}

} // namespace vr8::spinestill
