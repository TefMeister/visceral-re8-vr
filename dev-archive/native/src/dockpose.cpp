// dockpose.cpp -- see dockpose.h
#include "dockpose.h"
#include "bridge.h"
#include "gate.h"
#include "rack_right.h"
#include "joints.h"
#include "json_mini.h"
#include "player.h"
#include "settings.h"
#include "shellclip.h"
#include "smooth.h"
#include "zones.h"

#include <windows.h>

#include <cmath>
#include <filesystem>
#include <map>
#include <string>

namespace vn::dockpose {

using namespace joints;
using namespace vn::settings;

namespace {
struct Pose { float x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0; };
std::map<std::string, std::map<std::string, Pose>> g_poses;   // gun number -> spot -> pose
std::filesystem::file_time_type g_mtime{};
float g_check_t = -10.0f;
Pose g_cur, g_cur_r;                                            // what is applied now (left, right), eased toward the spot's numbers
int g_last_spot = -1, g_last_spot_r = -1;
// b102 (DOCK_POSE_RIDES_GLIDE): a left spot change that came with a glide of the hand (smooth.cpp) goes from what was applied
// then to the new spot's numbers on the glide's own curve, so the hand's place and Hand Poser's offset arrive together
Pose g_ride_from;
bool g_ride = false;
float g_ride_u0 = 0.0f;   // the glide's progress when the ride was anchored (a spot change mid-glide rides the rest of it)
int g_ride_glide = -1;    // the glide ridden: a new glide re-anchors from what is applied now, never back to the old start
void ride_anchor(const Pose& now) { g_ride = true; g_ride_from = now; g_ride_u0 = smooth::progress(); g_ride_glide = smooth::glide_id(); }

std::filesystem::path file_path() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    return std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "dock_poses.json";
}

void refresh() {   // at most once a second: re-read dock_poses.json when the window saved it
    const float t = now_s();
    if (t - g_check_t < DOCK_POSE_FILE_CHECK_S) return;
    g_check_t = t;
    std::error_code ec;
    const auto p = file_path();
    const auto mt = std::filesystem::last_write_time(p, ec);
    if (ec || mt == g_mtime) return;
    json::Value v;
    if (!json::load_file(p.wstring(), v) || v.kind != json::Value::OBJ) return;   // caught mid-write: the next check reads it
    g_mtime = mt;
    g_poses.clear();
    int n = 0;
    for (const auto& [gun, spots] : v.obj) {
        if (spots.kind != json::Value::OBJ) continue;
        for (const auto& [spot, e] : spots.obj) {
            if (e.kind != json::Value::OBJ) continue;
            auto num = [&](const char* k) { const auto* x = e.get(k); return x != nullptr && x->kind == json::Value::NUM ? (float)x->n : 0.0f; };
            g_poses[gun][spot] = Pose{num("x"), num("y"), num("z"), num("rx"), num("ry"), num("rz")};
            ++n;
        }
    }
    LOGI("%s dockpose: dock_poses.json read: %d spot pose(s)", TAG, n);
}

// the docked spots (dockpose.h); 2000+N (inside a pair's start sphere, not taken) and 0 are not docked
// (10: the Wolfsbane's hammer; 101 / 102: the RIGHT hand at the Wolfsbane's cover / on the rifle's bolt, 2026-11-02)
// 2026-11-08: 11 / 12 the slide / pump / bolt at the back (12: a pistol's slide from the left), 13 a magazine in the left hand,
// 104 the RIGHT hand on the bolt at the back (pairs.cpp)
bool docked(int spot) { return (spot >= 3 && spot <= 13) || spot == 101 || spot == 102 || spot == 104 || (spot >= 1000 && spot < 2000); }

// 2026-11-08: an "at the back" spot with nothing saved for it keeps the spot it came from (so a tuned bolt hand does not drift off
// at the click); the magazine in hand has none: the hand is the controller's, as before
int base_spot(int spot) { return spot == 11 ? 3 : spot == 12 ? 8 : spot == 104 ? 102 : -1; }

Pose wanted(int gun, int spot) {
    if (!docked(spot)) return Pose{};
    auto g = g_poses.find(std::to_string(gun));
    if (g == g_poses.end()) return Pose{};
    auto s = g->second.find(std::to_string(spot));
    if (s != g->second.end()) return s->second;
    const int b = base_spot(spot);
    if (b < 0) return Pose{};
    s = g->second.find(std::to_string(b));
    return s == g->second.end() ? Pose{} : s->second;
}

bool zero(const Pose& p) {
    return std::fabs(p.x) + std::fabs(p.y) + std::fabs(p.z) < 1e-5f && std::fabs(p.rx) + std::fabs(p.ry) + std::fabs(p.rz) < 1e-3f;
}
} // namespace

void on_ik(MO* ik) {
    const auto& s = player::now();
    if (ik != s.ik_left && ik != s.ik_right) return;
    const bool left = ik == s.ik_left;
    if (left) refresh();
    const int raw = (int)(bridge::view(left ? bridge::S_LEFT_SPOT : bridge::S_RIGHT_SPOT) + 0.5f);
    const int spot = left ? raw : (raw > 0 && raw < 100 ? 100 + raw : 0);   // (2026-11-02: the right hand's spots as 101, 102)
    const int gun = (int)(bridge::view(bridge::S_WEAPON_NUM) + 0.5f);
    const Pose want = wanted(gun, spot);
    int& last = left ? g_last_spot : g_last_spot_r;
    Pose& cur = left ? g_cur : g_cur_r;
    if (spot != last) {
        if (docked(spot) && !zero(want)) LOGI("%s dockpose: gun %d spot %d (%s hand): wrist %.3f %.3f %.3f m, %.1f %.1f %.1f deg", TAG, gun, spot, left ? "left" : "right", want.x, want.y, want.z, want.rx, want.ry, want.rz);
        if (left && DOCK_POSE_RIDES_GLIDE && smooth::easing()) {
            ride_anchor(cur);
            LOGI("%s dockpose: spot %d -> %d moves with the hand's glide (at %.0f%%)", TAG, last, spot, g_ride_u0 * 100.0f);
        }
        last = spot;
    }
    if (left && g_ride && !smooth::easing()) g_ride = false;   // the glide is over: the per-solve ease below finishes the last bit
    // any new glide (also one that starts a frame after the spot changed) carries what is left of the spot change with it
    if (left && DOCK_POSE_RIDES_GLIDE && smooth::easing() && smooth::glide_id() != g_ride_glide) ride_anchor(cur);
    if (left && g_ride) {
        const float u = g_ride_u0 >= 0.999f ? 1.0f : (smooth::progress() - g_ride_u0) / (1.0f - g_ride_u0);
        const Pose& a = g_ride_from;
        cur.x = a.x + (want.x - a.x) * u; cur.y = a.y + (want.y - a.y) * u; cur.z = a.z + (want.z - a.z) * u;
        cur.rx = a.rx + (want.rx - a.rx) * u; cur.ry = a.ry + (want.ry - a.ry) * u; cur.rz = a.rz + (want.rz - a.rz) * u;
    } else {
        const float k = DOCK_POSE_EASE;   // per arm solve: a short ease, so a slider change (or a spot change with no glide) never snaps
        cur.x += (want.x - cur.x) * k; cur.y += (want.y - cur.y) * k; cur.z += (want.z - cur.z) * k;
        cur.rx += (want.rx - cur.rx) * k; cur.ry += (want.ry - cur.ry) * k; cur.rz += (want.rz - cur.rz) * k;
    }
    // 2026-11-07 (Animation & Timing): the whole-hand move keyed into the finger clip playing on this hand (shellclip.h), on top
    Pose tot = cur;
    float hn[6]{};
    if (shellclip::hand_nudge(left, hn)) { tot.x += hn[0]; tot.y += hn[1]; tot.z += hn[2]; tot.rx += hn[3]; tot.ry += hn[4]; tot.rz += hn[5]; }
    if (zero(tot)) return;
    MO* target = field_obj(ik, "Target");
    Vec3 lp;
    Quat lq, gq;
    // the gun's turn: as WE place it while the left hand holds it (2026-11-02: the game's transform follows the right hand then);
    // 2026-11-07: else the gun's own transform (the right hand holds it: the hammer, STAY, a plain dock)
    if (target == nullptr || !player::get_pose(target, lp, lq)) return;
    if (!(gate::gun_rot(gq) || rack_right::gun_rot(gq) || zones::gun_rot(gq))) {
        Vec3 gp;
        if (s.weapon_tf == nullptr || !player::get_pose(s.weapon_tf, gp, gq)) return;
    }
    gq = qnorm(gq);
    const float d = 3.14159265f / 360.0f;   // half a degree in radians: quaternion halves
    const Quat local = qnorm(qmul(qmul(Quat{0, std::sin(tot.ry * d), 0, std::cos(tot.ry * d)}, Quat{std::sin(tot.rx * d), 0, 0, std::cos(tot.rx * d)}),
                                  Quat{0, 0, std::sin(tot.rz * d), std::cos(tot.rz * d)}));
    const Quat turn = qnorm(qmul(qmul(gq, local), qinv(gq)));   // about the gun's own axes, at the wrist
    player::set_pose(target, lp + rotate(gq, Vec3{tot.x, tot.y, tot.z}), qnorm(qmul(turn, qnorm(lq))));
}

} // namespace vn::dockpose
