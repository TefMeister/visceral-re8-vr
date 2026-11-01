// forearm.cpp -- see forearm.h
#include "forearm.h"
#include "joints.h"
#include "player.h"
#include "settings.h"

#include <string>

namespace vn::forearm {

using namespace joints;
using namespace vn::settings;

namespace {
const wchar_t* const NAMES[] = {L"L_Forearm_Twist_0", L"L_Forearm_Twist_1", L"L_Forearm_Twist_2", L"L_Forearm_Twist_3"};
constexpr int N = 4;
MO* g_tf = nullptr;
MO* g_joint[N] = {};
Quat g_hold[N] = {};
bool g_have = false;
int g_frames = 0;
std::string g_gun;

void write() {
    for (int i = 0; i < N; ++i)
        if (g_joint[i] != nullptr) set_any(JOINT, g_joint[i], "set_LocalRotation", &g_hold[i]);
}
} // namespace

void render_point() {
    if (!FOREARM_HOLD_ON) return;
    const auto& s = player::now();
    if (s.tf != g_tf) { g_tf = s.tf; for (auto& j : g_joint) j = nullptr; g_have = false; }
    if (g_tf == nullptr || s.weapon == nullptr || s.weapon_id.empty()) { g_have = false; g_frames = 0; g_gun.clear(); return; }
    if (s.weapon_id != g_gun) { g_gun = s.weapon_id; g_have = false; g_frames = 0; }
    if (!g_have) {
        if (++g_frames < FOREARM_SETTLE_FRAMES) return;   // the draw settles first: its pose is the one kept
        int found = 0;
        for (int i = 0; i < N; ++i) {
            if (g_joint[i] == nullptr) g_joint[i] = joint_by_name(g_tf, NAMES[i]);
            Quat q;
            if (g_joint[i] != nullptr && get_q(JOINT, g_joint[i], "get_LocalRotation", q)) { g_hold[i] = qnorm(q); ++found; }
            else g_joint[i] = nullptr;
        }
        g_have = true;
        LOGI("%s forearm: %s: the left forearm's %d twist joints kept as they are now, for as long as this gun is in hand", TAG, g_gun.c_str(), found);
    }
    write();
}

void begin_render() {
    if (FOREARM_HOLD_ON && g_have) write();
}

} // namespace vn::forearm
