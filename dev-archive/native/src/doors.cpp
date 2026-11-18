// doors.cpp -- see doors.h. Built from visceral-re2-vr dev-archive/native/src/hands/doorpush.cpp (2026-11-16).
#include "doors.h"
#include "bridge.h"
#include "common.h"
#include "joints.h"
#include "player.h"
#include "settings.h"

#include <cmath>
#include <cstdio>

namespace vn::doors {

using namespace vn::settings;
using namespace vn::joints;

namespace {
constexpr float DEG = 3.14159265f / 180.0f;

struct Leaf {
    MO* comp = nullptr;       // app.DoorBehavior
    MO* tf = nullptr;         // its GameObject's transform (the shut leaf's frame)
    MO* hinge = nullptr;      // the joint "_00"
    bool active = false;      // the game has it open (or is opening it)
    float drawn = 0.0f;       // our angle, degrees, 0..DOORS_MAX_DEG
    float written = 0.0f;     // the local yaw we last wrote (signed degrees)
    bool wrote = false;
    float game = 0.0f;        // the game's own angle, last seen written (unsigned degrees)
    float sign = 0.0f;        // which way the game turns the joint to open it
    float hand_prev[2] = {0, 0};
    bool hand_prev_ok[2] = {false, false};
};
Leaf g_leaves[DOORS_MAX_LEAVES];
float g_last_scan = -10.0f, g_last_touch = -10.0f, g_log_t = -10.0f;
float g_press_seq = 0.0f;
int g_logs = 0;

void say(const char* fmt, float a = 0, float b = 0, float c = 0, float d = 0) {
    if (g_logs >= 120) return;
    ++g_logs;
    char line[240];
    std::snprintf(line, sizeof line, fmt, a, b, c, d);
    LOGI("%s doors: %s", TAG, line);
}

MO* scene() {
    static API::Method* cur = API::get()->tdb()->find_method("via.SceneManager", "get_CurrentScene");
    void* sm = API::get()->get_native_singleton("via.SceneManager");
    if (cur == nullptr || sm == nullptr) return nullptr;
    return (MO*)cur->call<void*>(API::get()->get_vm_context(), sm);
}

float yaw_of_local(MO* joint) {   // the joint's local turn about Y, degrees
    Quat q;
    if (!get_q(JOINT, joint, "get_LocalRotation", q)) return 0.0f;
    return 2.0f * std::atan2(q.y, q.w) / DEG;
}
void set_local_yaw(Leaf& d, float deg) {
    const float a = deg * DEG * 0.5f;
    const Quat q{0.0f, std::sin(a), 0.0f, std::cos(a)};
    set_any(JOINT, d.hinge, "set_LocalRotation", &q);
    d.written = deg;
    d.wrote = true;
}

// a world point's angle around the hinge from the shut leaf, in the opening direction, and its distance on the level
bool angle_of(const Leaf& d, Vec3 p, float& deg, float& r) {
    Vec3 h;
    Quat q;
    if (!get_v3(JOINT, d.hinge, "get_Position", h) || !get_q(XFORM, d.tf, "get_Rotation", q)) return false;
    const Vec3 l = rotate(qinv(qnorm(q)), p - h);
    r = std::sqrt(l.x * l.x + l.z * l.z);
    const float s = DOORS_LEAF_SIDE;
    const float t = std::atan2(-l.z * s, l.x * s) / DEG;   // the leaf at local yaw t lies along (s cos t, 0, -s sin t)
    deg = t * (d.sign != 0.0f ? d.sign : 1.0f);
    return true;
}

bool hand_world(int i, Vec3& out) {
    Quat q;
    if (player::motion_joint(i == 0 ? "l_arm_wrist" : "r_arm_wrist", out, q)) return true;
    if (!bridge::flag(bridge::S_HANDS_W_OK)) return false;
    out = bridge::view_vec3(i == 0 ? bridge::S_LHAND_W : bridge::S_RHAND_W);
    return std::isfinite(out.x) && std::isfinite(out.z);   // world metres: not bridge::has(), which stops at 499
}
bool player_pos(Vec3& out) { return get_v3(XFORM, player::now().tf, "get_Position", out); }

bool locked(MO* comp) { return call_direct<bool>(comp, "IsLocked", false); }

void scan() {
    Vec3 pp;
    if (!player_pos(pp)) return;
    auto* sc = scene();
    auto* rt = API::get()->typeof("app.DoorBehavior");
    if (sc == nullptr || rt == nullptr) { say("no scene or no app.DoorBehavior type: nothing to push"); return; }
    MO* list = call_ptr(sc, "findComponents(System.Type)", {rt});
    const int k = call_direct<int>(list, "get_Count", 0);
    // the nearest leaves, nearest first
    MO* best[DOORS_MAX_LEAVES] = {};
    float best_d[DOORS_MAX_LEAVES];
    for (float& x : best_d) x = DOORS_SCAN_M;
    for (int i = 0; i < k; ++i) {
        MO* c = call_ptr(list, "get_Item", {(void*)(intptr_t)i});
        MO* go = call_ptr(c, "get_GameObject");
        Vec3 p;
        if (go == nullptr || !get_v3(XFORM, call_ptr(go, "get_Transform"), "get_Position", p)) continue;
        if (std::fabs(p.y - pp.y) > DOORS_SCAN_UP_M) continue;   // another floor
        const float dd = std::sqrt((p.x - pp.x) * (p.x - pp.x) + (p.z - pp.z) * (p.z - pp.z));
        for (int j = 0; j < DOORS_MAX_LEAVES; ++j) {
            if (dd >= best_d[j]) continue;
            for (int m = DOORS_MAX_LEAVES - 1; m > j; --m) { best[m] = best[m - 1]; best_d[m] = best_d[m - 1]; }
            best[j] = c;
            best_d[j] = dd;
            break;
        }
    }
    // keep the ones still near, or still drawn open and not far; take the new ones into free places
    for (Leaf& d : g_leaves) {
        if (d.comp == nullptr) continue;
        bool near = false;
        for (MO* c : best) near = near || c == d.comp;
        if (near) continue;
        if (!d.active) { d = Leaf{}; continue; }
        Vec3 h;
        if (!get_v3(JOINT, d.hinge, "get_Position", h) || dist(h, pp) > DOORS_RELEASE_M) {
            say("an open door left behind (%.0f deg): left as drawn", d.drawn);
            d = Leaf{};
        }
    }
    for (int j = 0; j < DOORS_MAX_LEAVES; ++j) {
        if (best[j] == nullptr) continue;
        bool have = false;
        for (Leaf& d : g_leaves) have = have || d.comp == best[j];
        if (have) continue;
        for (Leaf& d : g_leaves) {
            if (d.comp != nullptr) continue;
            d.comp = best[j];
            d.tf = call_ptr(call_ptr(best[j], "get_GameObject"), "get_Transform");
            d.hinge = joint_by_name(d.tf, DOORS_HINGE);
            if (d.hinge == nullptr) { say("a door leaf with no joint _00: left alone"); d = Leaf{}; break; }
            d.game = std::fabs(yaw_of_local(d.hinge));
            say("a door leaf %.1f m away (%.0f leaves in the scene), its angle %.1f deg", best_d[j], (float)k, d.game);
            break;
        }
    }
}
} // namespace

void frame() {
    if (!DOORS_ON || !bridge::live()) return;
    const float t = now_s();
    if (t - g_last_scan >= DOORS_SCAN_S) { g_last_scan = t; scan(); }
    if (!DOORS_TOUCH_OPENS || t - g_last_touch < DOORS_TOUCH_COOLDOWN_S) return;
    // a hand pressing on a shut leaf, moving into it: A for the game
    for (Leaf& d : g_leaves) {
        if (d.comp == nullptr || d.active) continue;
        for (int i = 0; i < 2; ++i) {
            Vec3 hp;
            float a, r;
            if (!hand_world(i, hp) || !angle_of(d, hp, a, r)) { d.hand_prev_ok[i] = false; continue; }
            const float m = std::asin(std::fmin(1.0f, DOORS_HAND_R / std::fmax(r, DOORS_HAND_R))) / DEG;
            const bool touching = r >= 0.12f && r <= DOORS_LEAF_M && std::fabs(a) <= m;
            const bool closing_in = d.hand_prev_ok[i] && std::fabs(a) < std::fabs(d.hand_prev[i]);
            d.hand_prev[i] = a;
            d.hand_prev_ok[i] = true;
            if (touching && closing_in) {
                g_last_touch = t;
                if (locked(d.comp)) { say("a hand on a LOCKED door (%.2f m from the hinge): no A", r); return; }
                g_press_seq += 1.0f;
                bridge::put(bridge::S_DOOR_PRESS_SEQ, g_press_seq);
                say("a hand on a shut door (%.2f m from the hinge): A for the game", r);
                return;
            }
        }
    }
}

void late_point() {
    if (!DOORS_ON) return;
    Vec3 pp;
    const bool have_pp = player_pos(pp);
    for (Leaf& d : g_leaves) {
        if (d.comp == nullptr || d.hinge == nullptr) continue;
        const float raw = yaw_of_local(d.hinge);
        // the game wrote the joint this frame when it is not what we left there (or we have not drawn it yet)
        const bool game_wrote = !d.wrote || std::fabs(raw - d.written) > 0.05f;
        const float prev = d.game;
        if (game_wrote) d.game = std::fabs(raw);
        if (!d.active) {
            if (game_wrote && d.game > DOORS_OPEN_SEEN_DEG) {
                d.active = true;
                d.sign = raw < 0.0f ? -1.0f : 1.0f;
                d.drawn = DOORS_INITIAL_DEG;
                d.hand_prev_ok[0] = d.hand_prev_ok[1] = false;
                say("the game opened a door (it turns %.0f): drawn at %.0f deg, the hands and the body push it from here", d.sign, DOORS_INITIAL_DEG);
            } else {
                d.wrote = false;   // never drawn while shut: the next read is the game's own again
                continue;
            }
        }
        // the game closing it (its own angle falling): ours goes down with it once it is under ours; shut = done
        if (game_wrote && d.game < prev - 0.05f && d.game < d.drawn) d.drawn = d.game;
        if (game_wrote && d.game < 0.2f) {
            say("the game shut the door: ours too");
            d.active = false;
            d.drawn = 0.0f;
            d.wrote = false;
            continue;
        }
        // the hands: a hand that crossed the leaf since last frame, or is on it, pushes it to just past itself
        for (int i = 0; i < 2; ++i) {
            Vec3 hp;
            float a, r;
            if (!hand_world(i, hp) || !angle_of(d, hp, a, r) || r < 0.12f || r > DOORS_LEAF_M + DOORS_HAND_R) { d.hand_prev_ok[i] = false; continue; }
            const float m = std::asin(std::fmin(1.0f, DOORS_HAND_R / r)) / DEG;
            const bool crossed = d.hand_prev_ok[i] && d.hand_prev[i] <= d.drawn + m && a + m > d.drawn;
            const bool on_it = std::fabs(a - d.drawn) <= m;
            if ((crossed || on_it) && a + m > d.drawn && a + m < DOORS_MAX_DEG + 20.0f) d.drawn = std::fmin(DOORS_MAX_DEG, a + m);
            d.hand_prev[i] = a;
            d.hand_prev_ok[i] = true;
        }
        // the body: never drawn through the player standing in the doorway
        float a, r;
        if (have_pp && angle_of(d, pp, a, r) && r > DOORS_BODY_R && r < DOORS_LEAF_M + DOORS_BODY_R) {
            const float m = std::asin(std::fmin(1.0f, DOORS_BODY_R / r)) / DEG;
            if (a + m > d.drawn && a - m < DOORS_MAX_DEG) d.drawn = std::fmin(DOORS_MAX_DEG, a + m);
        }
        set_local_yaw(d, d.sign * d.drawn);
        const float t = now_s();
        if (t - g_log_t > 1.0f) { g_log_t = t; say("a door drawn at %.1f deg, the game's %.1f", d.drawn, d.game); }
    }
}

void render_point() {
    if (!DOORS_ON) return;
    for (Leaf& d : g_leaves) if (d.active && d.hinge != nullptr) set_local_yaw(d, d.sign * d.drawn);
}

} // namespace vn::doors
