// forearm.cpp -- see forearm.h
#include "forearm.h"
#include "joints.h"
#include "player.h"
#include "settings.h"

#include <cmath>
#include <string>

namespace vn::forearm {

using namespace joints;
using namespace vn::settings;

namespace {
const wchar_t* const NAMES[] = {L"L_Forearm_Twist_0", L"L_Forearm_Twist_1", L"L_Forearm_Twist_2", L"L_Forearm_Twist_3"};
constexpr int N = 4;
constexpr float DEG = 3.14159265f / 180.0f;
MO* g_tf = nullptr;
MO* g_joint[N] = {};
MO* g_forearm = nullptr;          // L_Forearm: the frame the twist is worked out in
MO* g_hand = nullptr;             // L_Hand (its parent is L_Forearm, measured: armstretch finds 2 joints elbow to hand)
Quat g_hold[N] = {};              // each twist joint's local turn when the gun settled (b094's held pose = zero twist)
int g_parent[N] = {};             // -1 = L_Forearm, k = twist joint k, -2 = unknown (that joint is only held, never turned)
Quat g_holdF[N] = {};             // each twist joint's held turn in L_Forearm's frame
float g_share[N] = {};            // how much of the hand's twist each joint takes: its place along the forearm, 0 elbow .. 1 wrist
Vec3 g_axis{1, 0, 0};             // the forearm's long axis in L_Forearm's frame (toward the hand)
float g_ref = 0.0f;               // the hand's twist about the axis when the gun settled
float g_twist = 0.0f;             // the twist shared out now (radians, unwrapped, eased)
bool g_follow = false;            // the layout was understood: the twist follows the hand
bool g_have = false;
int g_frames = 0;
int g_logged = 0;
std::string g_gun;

float vlen(Vec3 v) { return std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z); }
float dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
Quat axis_angle(Vec3 a, float rad) { const float s = std::sin(rad * 0.5f); return {a.x * s, a.y * s, a.z * s, std::cos(rad * 0.5f)}; }

// the hand's turn about the forearm's axis (the twist part of a swing-twist split), radians in (-pi, pi]
bool hand_twist(float& out) {
    Quat q;
    if (g_hand == nullptr || !get_q(JOINT, g_hand, "get_LocalRotation", q)) return false;
    q = qnorm(q);
    const float p = dot({q.x, q.y, q.z}, g_axis);
    if (std::fabs(p) < 1e-6f && std::fabs(q.w) < 1e-6f) return false;   // a half turn sideways: no twist to read
    out = wrap_pi(2.0f * std::atan2(p, q.w));
    return true;
}

// learn where the twist joints hang and how far along the forearm each sits; false = keep the old plain hold
bool learn_layout() {
    g_forearm = joint_by_name(g_tf, L"L_Forearm");
    g_hand = joint_by_name(g_tf, L"L_Hand");
    if (g_forearm == nullptr || g_hand == nullptr) return false;
    if (call_ptr(g_hand, "get_Parent") != g_forearm) { LOGW("%s forearm: L_Hand does not hang from L_Forearm: twist not followed, held only", TAG); return false; }
    Vec3 hp;
    if (!get_v3(JOINT, g_hand, "get_LocalPosition", hp) || vlen(hp) < 0.02f) return false;
    const float arm = vlen(hp);
    g_axis = hp * (1.0f / arm);
    for (int i = 0; i < N; ++i) {
        g_parent[i] = -2;
        if (g_joint[i] == nullptr) continue;
        MO* p = call_ptr(g_joint[i], "get_Parent");
        if (p == g_forearm) g_parent[i] = -1;
        for (int k = 0; k < N; ++k) if (k != i && p != nullptr && p == g_joint[k]) g_parent[i] = k;
    }
    // each joint's held turn and place in L_Forearm's frame, parents first (at most N passes)
    Vec3 posF[N] = {};
    bool done[N] = {};
    for (int pass = 0; pass < N; ++pass)
        for (int i = 0; i < N; ++i) {
            if (done[i] || g_parent[i] == -2) continue;
            const int pa = g_parent[i];
            if (pa >= 0 && !done[pa]) continue;
            Vec3 lp{0, 0, 0};
            get_v3(JOINT, g_joint[i], "get_LocalPosition", lp);
            if (pa == -1) { g_holdF[i] = g_hold[i]; posF[i] = lp; }
            else { g_holdF[i] = qnorm(qmul(g_holdF[pa], g_hold[i])); posF[i] = posF[pa] + rotate(g_holdF[pa], lp); }
            done[i] = true;
        }
    int used = 0;
    for (int i = 0; i < N; ++i) {
        if (!done[i]) { g_parent[i] = -2; g_share[i] = 0.0f; continue; }
        float t = dot(posF[i], g_axis) / arm;
        g_share[i] = (t < 0.0f ? 0.0f : t > 1.0f ? 1.0f : t) * FOREARM_TWIST_SHARE;
        ++used;
    }
    if (used == 0) return false;
    LOGI("%s forearm: twist follows the hand: axis (%.2f %.2f %.2f), shares %.2f %.2f %.2f %.2f, parents %d %d %d %d", TAG,
         g_axis.x, g_axis.y, g_axis.z, g_share[0], g_share[1], g_share[2], g_share[3], g_parent[0], g_parent[1], g_parent[2], g_parent[3]);
    return true;
}

// the twist to share out now: the hand's twist since the gun settled, unwrapped (no flip at a half turn), capped, eased
void follow() {
    float now;
    if (!hand_twist(now)) return;
    const float want_raw = g_twist + wrap_pi(now - g_ref - g_twist);   // nearest to where we are: never a jump across +-180
    const float cap = FOREARM_TWIST_MAX_DEG * DEG;
    const float want = want_raw > cap ? cap : want_raw < -cap ? -cap : want_raw;
    const float step = FOREARM_TWIST_RATE_DEG * DEG;
    const float d = want - g_twist;
    if (std::fabs(d) > step && g_logged < 20) {
        ++g_logged;
        LOGI("%s forearm: the hand turned %.0f deg in one frame: the forearm follows at %.0f deg a frame", TAG, d / DEG, FOREARM_TWIST_RATE_DEG);
    }
    g_twist += d > step ? step : d < -step ? -step : d;
}

void write() {
    Quat nowF[N];
    for (int i = 0; i < N; ++i)   // all in L_Forearm's frame first: a parent may come later in the list
        nowF[i] = qnorm(qmul(axis_angle(g_axis, g_twist * g_share[i]), g_holdF[i]));
    for (int i = 0; i < N; ++i) {
        if (g_joint[i] == nullptr) continue;
        Quat q = g_hold[i];
        if (g_follow && g_parent[i] != -2)
            q = g_parent[i] == -1 ? nowF[i] : qnorm(qmul(qinv(nowF[g_parent[i]]), nowF[i]));
        set_any(JOINT, g_joint[i], "set_LocalRotation", &q);
    }
}
} // namespace

void render_point() {
    if (!FOREARM_HOLD_ON) return;
    const auto& s = player::now();
    if (s.tf != g_tf) { g_tf = s.tf; for (auto& j : g_joint) j = nullptr; g_forearm = g_hand = nullptr; g_have = false; }
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
        g_twist = 0.0f;
        g_follow = FOREARM_TWIST_FOLLOW_ON && learn_layout() && hand_twist(g_ref);
        LOGI("%s forearm: %s: the left forearm's %d twist joints kept as they are now, %s", TAG, g_gun.c_str(), found,
             g_follow ? "and turned with the hand's twist from here" : "for as long as this gun is in hand (not following the hand)");
    }
    write();   // the twist as last worked out: the hand is read only once a frame, after the arm solves (below)
}

void begin_render() {
    if (!FOREARM_HOLD_ON || !g_have) return;
    if (g_follow) follow();   // once a frame, on the solved hand: two reads at two moments would rock the twist back and forth
    write();
}

} // namespace vn::forearm
