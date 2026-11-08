// armstretch.cpp -- see armstretch.h
#include "armstretch.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "settings.h"

#include <cmath>

namespace vn::armstretch {

using namespace joints;
using namespace vn::settings;

namespace {
constexpr int MAXJ = 8;            // the joints from the elbow down to the hand (the forearm, its twist joints, the hand)
MO* g_tf = nullptr;
MO* g_upper = nullptr;             // L_UpperArm: the shoulder end of the arm
MO* g_chain[MAXJ] = {};            // L_Hand and its parents up to (not including) L_UpperArm
int g_n = 0;
bool g_looked = false;
Vec3 g_rest[MAXJ] = {};            // each joint's own (local) place on its parent's bone, as the game last had it
Vec3 g_wrote[MAXJ] = {};           // what we wrote last (a game that leaves the joint alone must not make the stretch grow)
bool g_have_rest[MAXJ] = {};
float g_k = 1.0f;                  // the stretch applied now (1 = the game's own arm)
int g_logged = 0;

float len(Vec3 v) { return std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z); }

void find_chain() {
    g_looked = true;
    g_n = 0;
    g_upper = joint_by_name(g_tf, L"L_UpperArm");
    MO* j = joint_by_name(g_tf, L"L_Hand");
    while (j != nullptr && g_upper != nullptr && j != g_upper && g_n < MAXJ) {
        g_chain[g_n] = j;
        g_have_rest[g_n] = false;
        ++g_n;
        j = call_ptr(j, "get_Parent");
    }
    if (j != g_upper) { LOGW("%s armstretch: L_Hand's parents do not reach L_UpperArm within %d joints: no rubber arm", TAG, MAXJ); g_n = 0; return; }
    LOGI("%s armstretch: the left arm's %d joints from the elbow to the hand found", TAG, g_n);
}

bool left_on_gun() { return bridge::view(bridge::S_LEFT_SPOT) > 0.5f || bridge::flag(bridge::S_GRIPPING_WEAPON); }

void write(float k) {
    for (int i = 0; i < g_n; ++i) {
        if (!g_have_rest[i]) continue;
        const Vec3 p = g_rest[i] * k;
        set_any(JOINT, g_chain[i], "set_LocalPosition", &p);
        g_wrote[i] = p;
    }
}
} // namespace

void render_point() {
    if (!ARM_STRETCH_ON) return;
    const auto& s = player::now();
    if (s.tf != g_tf) { g_tf = s.tf; g_looked = false; g_n = 0; g_k = 1.0f; }
    if (g_tf == nullptr || s.ik_left == nullptr) return;
    if (!g_looked) find_chain();
    if (g_n == 0) return;
    // the rest: what the game has there now, unless it is still what we wrote (then the game left it alone: keep ours)
    float arm = 0.0f;
    for (int i = 0; i < g_n; ++i) {
        Vec3 p;
        if (!get_v3(JOINT, g_chain[i], "get_LocalPosition", p)) return;
        const bool ours = g_have_rest[i] && len(p - g_wrote[i]) < 1e-5f;
        if (!ours) { g_rest[i] = p; g_have_rest[i] = true; }
        arm += len(g_rest[i]);
    }
    // the upper arm's own length is the first chain joint's place on it (the elbow); the rest add up to the hand
    float want = 1.0f;
    Vec3 sp, tp;
    Quat tq;
    if (left_on_gun() && arm > 0.05f && get_v3(JOINT, g_upper, "get_Position", sp) && player::get_pose(field_obj(s.ik_left, "Target"), tp, tq)) {
        const float d = len(tp - sp);
        if (d > arm * ARM_STRETCH_FROM) want = std::fmin(ARM_STRETCH_MAX, d / arm);
    }
    g_k += (want - g_k) * ARM_STRETCH_EASE;
    if (std::fabs(g_k - 1.0f) < 0.002f && want == 1.0f) {
        if (g_k != 1.0f) { g_k = 1.0f; write(1.0f); }
        return;
    }
    if (g_logged < 20 && want > 1.0f && g_k < 1.01f) { ++g_logged; LOGI("%s armstretch: the left hand is past the arm's reach: the arm stretches (x%.2f)", TAG, want); }
    write(g_k);
}

void begin_render() {
    if (!ARM_STRETCH_ON || g_n == 0 || g_k == 1.0f) return;
    write(g_k);
}

} // namespace vn::armstretch
