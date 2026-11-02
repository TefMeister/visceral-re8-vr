// shellclip.cpp -- see shellclip.h. (2026-11-02)
#include "shellclip.h"

#include <windows.h>

#include <array>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <map>
#include <sstream>
#include <vector>

#include "common.h"
#include "joints.h"
#include "player.h"
#include "settings.h"

namespace vn::shellclip {

using namespace joints;
using namespace vn::settings;

namespace {
constexpr int N = 15;
const wchar_t* LEFT_FINGERS[N] = {
    L"L_IndexF1", L"L_IndexF2", L"L_IndexF3", L"L_MiddleF1", L"L_MiddleF2", L"L_MiddleF3",
    L"L_RingF1", L"L_RingF2", L"L_RingF3", L"L_PinkyF1", L"L_PinkyF2", L"L_PinkyF3",
    L"L_Thumb1", L"L_Thumb2", L"L_Thumb3",
};

struct Clip { std::vector<float> t; std::vector<std::array<Quat, N>> q; bool ok = false; };
std::map<std::string, Clip> g_clips;   // by short gun id; a missing file is remembered as not ok

const Clip* g_clip = nullptr;
float g_t0 = -1.0f;            // when the current play started (now_s)
MO* g_tf = nullptr;
MO* g_joint[N] = {};
Quat g_found[N] = {};          // the pose at the start, to blend in from
Quat g_target[N] = {};
bool g_have = false;

std::filesystem::path data_dir() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    return std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "clips";
}

std::string short_id(const std::string& id) {
    const auto k = id.find('_');
    return k == std::string::npos ? id : id.substr(0, k);
}

const Clip* load(const std::string& gun) {
    auto it = g_clips.find(gun);
    if (it != g_clips.end()) return it->second.ok ? &it->second : nullptr;
    Clip& c = g_clips[gun];
    std::ifstream f(data_dir() / (gun + "_round_in.csv"));
    if (!f) { LOGI("%s shellclip: no clip for %s (clips/%s_round_in.csv): the fingers stay as they are", TAG, gun.c_str(), gun.c_str()); return nullptr; }
    std::string line;
    std::getline(f, line);   // header: t + 15 joints x 4, in LEFT_FINGERS order (make_finger_clip.py)
    while (std::getline(f, line)) {
        std::stringstream ss(line);
        std::string cell;
        std::vector<float> v;
        while (std::getline(ss, cell, ',')) v.push_back(std::strtof(cell.c_str(), nullptr));
        if (v.size() != 1 + N * 4) continue;
        c.t.push_back(v[0]);
        std::array<Quat, N> q{};
        for (int i = 0; i < N; ++i) q[i] = qnorm({v[1 + i * 4], v[2 + i * 4], v[3 + i * 4], v[4 + i * 4]});
        c.q.push_back(q);
    }
    c.ok = c.t.size() >= 2;
    LOGI("%s shellclip: %s clip %s: %d frames, %.2f s", TAG, gun.c_str(), c.ok ? "loaded" : "UNUSABLE", (int)c.t.size(), c.ok ? c.t.back() : 0.0f);
    return c.ok ? &c : nullptr;
}

Quat nlerp(Quat a, Quat b, float u) {
    if (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w < 0.0f) b = {-b.x, -b.y, -b.z, -b.w};
    return qnorm({a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, a.z + (b.z - a.z) * u, a.w + (b.w - a.w) * u});
}

// the clip's pose at time t (linear between recorded frames)
void sample(const Clip& c, float t, Quat out[N]) {
    size_t k = 0;
    while (k + 1 < c.t.size() && c.t[k + 1] <= t) ++k;
    if (k + 1 >= c.t.size()) { for (int i = 0; i < N; ++i) out[i] = c.q.back()[i]; return; }
    const float span = c.t[k + 1] - c.t[k];
    const float u = span > 0.0f ? (t - c.t[k]) / span : 0.0f;
    for (int i = 0; i < N; ++i) out[i] = nlerp(c.q[k][i], c.q[k + 1][i], u);
}

void write_all() {
    for (int i = 0; i < N; ++i)
        if (g_joint[i] != nullptr) set_any(JOINT, g_joint[i], "set_LocalRotation", &g_target[i]);
}
} // namespace

void play(const std::string& gun_id) {
    const auto gun = short_id(gun_id);
    const Clip* c = load(gun);
    if (c == nullptr) return;
    g_clip = c;
    g_t0 = now_s();
    g_have = false;   // the starting pose is read at the next render point
    LOGI("%s shellclip: %s round in: the game's finger movement plays (%.2f s)", TAG, gun.c_str(), c->t.back());
}

bool playing() { return g_clip != nullptr; }

void frame() {
    static float last_check = -1.0f;
    const float t = now_s();
    if (t - last_check < 0.25f) return;
    last_check = t;
    const auto p = data_dir() / "play.txt";
    std::ifstream f(p);
    std::string id;
    if (f && std::getline(f, id) && !id.empty()) {
        f.close();
        std::ofstream(p, std::ios::trunc).close();
        LOGI("%s shellclip: test play asked for %s", TAG, id.c_str());
        play(id);
    }
}

void render_point() {
    if (g_clip == nullptr) return;
    const auto& s = player::now();
    if (s.tf == nullptr) { g_clip = nullptr; return; }
    if (s.tf != g_tf) { g_tf = s.tf; for (auto& j : g_joint) j = nullptr; }
    for (int i = 0; i < N; ++i) if (g_joint[i] == nullptr) g_joint[i] = joint_by_name(g_tf, LEFT_FINGERS[i]);
    const float t = now_s() - g_t0;
    const float len = g_clip->t.back();
    if (!g_have) {   // the pose the hand had when the round went in: blended in from
        for (int i = 0; i < N; ++i) {
            Quat q{0, 0, 0, 1};
            if (g_joint[i] != nullptr && get_q(JOINT, g_joint[i], "get_LocalRotation", q)) g_found[i] = qnorm(q);
            else g_found[i] = q;
        }
        g_have = true;
    }
    if (t >= len + SHELLCLIP_BLEND_S) {   // done: the other finger code takes the hand back from the next frame
        g_clip = nullptr;
        LOGI("%s shellclip: finished", TAG);
        return;
    }
    Quat pose[N];
    sample(*g_clip, std::fmin(t, len), pose);
    const float in = std::fmin(1.0f, t / SHELLCLIP_BLEND_S);
    const float out = t > len ? std::fmax(0.0f, 1.0f - (t - len) / SHELLCLIP_BLEND_S) : 1.0f;
    for (int i = 0; i < N; ++i) {
        // in: from the found pose to the clip; out: from the clip back toward the found pose (the others then take over)
        g_target[i] = nlerp(g_found[i], pose[i], ease(std::fmin(in, out)));
    }
    write_all();
}

void begin_render() {
    if (g_clip == nullptr || !g_have) return;
    write_all();
}

} // namespace vn::shellclip
