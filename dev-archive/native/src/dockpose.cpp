// dockpose.cpp -- see dockpose.h
#include "dockpose.h"
#include "bridge.h"
#include "joints.h"
#include "json_mini.h"
#include "player.h"
#include "settings.h"
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
Pose g_cur;                                                     // what is applied now, eased toward the spot's numbers
int g_last_spot = -1;

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
bool docked(int spot) { return (spot >= 3 && spot <= 9) || (spot >= 1000 && spot < 2000); }

Pose wanted(int gun, int spot) {
    if (!docked(spot)) return Pose{};
    auto g = g_poses.find(std::to_string(gun));
    if (g == g_poses.end()) return Pose{};
    auto s = g->second.find(std::to_string(spot));
    return s == g->second.end() ? Pose{} : s->second;
}

bool zero(const Pose& p) {
    return std::fabs(p.x) + std::fabs(p.y) + std::fabs(p.z) < 1e-5f && std::fabs(p.rx) + std::fabs(p.ry) + std::fabs(p.rz) < 1e-3f;
}
} // namespace

void on_ik(MO* ik) {
    const auto& s = player::now();
    if (ik != s.ik_left) return;
    refresh();
    const int spot = (int)(bridge::view(bridge::S_LEFT_SPOT) + 0.5f), gun = (int)(bridge::view(bridge::S_WEAPON_NUM) + 0.5f);
    const Pose want = wanted(gun, spot);
    if (spot != g_last_spot) {
        if (docked(spot) && !zero(want)) LOGI("%s dockpose: gun %d spot %d: wrist %.3f %.3f %.3f m, %.1f %.1f %.1f deg", TAG, gun, spot, want.x, want.y, want.z, want.rx, want.ry, want.rz);
        g_last_spot = spot;
    }
    const float k = DOCK_POSE_EASE;   // per arm solve: a short ease, so a change of spot (or of a slider) never snaps
    g_cur.x += (want.x - g_cur.x) * k; g_cur.y += (want.y - g_cur.y) * k; g_cur.z += (want.z - g_cur.z) * k;
    g_cur.rx += (want.rx - g_cur.rx) * k; g_cur.ry += (want.ry - g_cur.ry) * k; g_cur.rz += (want.rz - g_cur.rz) * k;
    if (zero(g_cur)) return;
    MO* target = field_obj(ik, "Target");
    Vec3 lp;
    Quat lq, gq;
    if (target == nullptr || !player::get_pose(target, lp, lq) || !zones::gun_rot(gq)) return;
    gq = qnorm(gq);
    const float d = 3.14159265f / 360.0f;   // half a degree in radians: quaternion halves
    const Quat local = qnorm(qmul(qmul(Quat{0, std::sin(g_cur.ry * d), 0, std::cos(g_cur.ry * d)}, Quat{std::sin(g_cur.rx * d), 0, 0, std::cos(g_cur.rx * d)}),
                                  Quat{0, 0, std::sin(g_cur.rz * d), std::cos(g_cur.rz * d)}));
    const Quat turn = qnorm(qmul(qmul(gq, local), qinv(gq)));   // about the gun's own axes, at the wrist
    player::set_pose(target, lp + rotate(gq, Vec3{g_cur.x, g_cur.y, g_cur.z}), qnorm(qmul(turn, qnorm(lq))));
}

} // namespace vn::dockpose
