// shellclip.cpp -- see shellclip.h. (2026-11-02; every gun, both hands, named events 2026-11-04)
#include "shellclip.h"

#include <windows.h>

#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

#include "bridge.h"
#include "common.h"
#include "joints.h"
#include "player.h"
#include "settings.h"

namespace vn::shellclip {

using namespace joints;
using namespace vn::settings;

namespace {
struct Clip {
    std::vector<std::wstring> names;          // the joints it moves, from the header (L_IndexF1 ... R_Thumb3)
    std::vector<float> t;
    std::vector<std::vector<Quat>> q;         // per frame, one per name
    bool ok = false, left = false, right = false;
};
std::map<std::string, Clip> g_clips;          // "<gun>_<event>"; a missing file is remembered as not ok

struct Play {
    const Clip* clip = nullptr;
    std::string what;                         // "<gun>_<event>", for the log
    float t0 = 0.0f;                          // when it started (now_s)
    std::vector<MO*> joint;
    std::vector<Quat> found, target;          // the pose at the start (blended in from / out to), and what is written
    bool have = false;
    bool left = false, right = false;         // the hands this play moves (the clip's, limited by play()'s hands)
    bool pulse = false;                       // a pulse (pulse()): found * turn(axis, deg * sin), no clip frames
    Vec3 axis{0, 0, 1};
    float deg = 0.0f;
};
std::vector<Play> g_plays;                    // at most one per hand (a both-hands clip counts for both)
MO* g_tf = nullptr;

std::filesystem::path data_dir() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    return std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "clips";
}

std::string short_id(const std::string& id) {
    const auto k = id.find('_');
    return k == std::string::npos ? id : id.substr(0, k);
}

const Clip* load(const std::string& gun, const std::string& event) {
    const std::string key = gun + "_" + event;
    auto it = g_clips.find(key);
    if (it != g_clips.end()) return it->second.ok ? &it->second : nullptr;
    Clip& c = g_clips[key];
    std::ifstream f(data_dir() / (key + ".csv"));
    if (!f) { LOGI("%s shellclip: no clip %s (clips/%s.csv): the fingers stay as they are", TAG, key.c_str(), key.c_str()); return nullptr; }
    std::string line;
    std::getline(f, line);   // header: t, then <joint>.x .y .z .w per joint (make_finger_book.py)
    {
        std::stringstream ss(line);
        std::string cell;
        int k = 0;
        while (std::getline(ss, cell, ',')) {
            const int col = k++;
            if (col == 0 || (col - 1) % 4 != 0) continue;   // one name per four columns, from the .x one
            const auto dot = cell.rfind('.');
            const std::string name = dot == std::string::npos ? cell : cell.substr(0, dot);
            c.names.push_back(widen(name.c_str()));
            if (name.rfind("L_", 0) == 0) c.left = true;
            if (name.rfind("R_", 0) == 0) c.right = true;
        }
    }
    const size_t n = c.names.size();
    while (std::getline(f, line)) {
        std::stringstream ss(line);
        std::string cell;
        std::vector<float> v;
        while (std::getline(ss, cell, ',')) v.push_back(std::strtof(cell.c_str(), nullptr));
        if (v.size() != 1 + n * 4) continue;
        c.t.push_back(v[0]);
        std::vector<Quat> q(n);
        for (size_t i = 0; i < n; ++i) q[i] = qnorm({v[1 + i * 4], v[2 + i * 4], v[3 + i * 4], v[4 + i * 4]});
        c.q.push_back(std::move(q));
    }
    c.ok = n > 0 && c.t.size() >= 2 && (c.left || c.right);
    LOGI("%s shellclip: clip %s %s: %d joints (%s%s), %d frames, %.2f s", TAG, key.c_str(), c.ok ? "loaded" : "UNUSABLE", (int)n,
         c.left ? "left" : "", c.right ? (c.left ? " + right" : "right") : "", (int)c.t.size(), c.ok ? c.t.back() : 0.0f);
    return c.ok ? &c : nullptr;
}

Quat nlerp(Quat a, Quat b, float u) {
    if (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w < 0.0f) b = {-b.x, -b.y, -b.z, -b.w};
    return qnorm({a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, a.z + (b.z - a.z) * u, a.w + (b.w - a.w) * u});
}

// the clip's pose at time t (linear between recorded frames)
void sample(const Clip& c, float t, std::vector<Quat>& out) {
    size_t k = 0;
    while (k + 1 < c.t.size() && c.t[k + 1] <= t) ++k;
    const size_t n = c.names.size();
    out.resize(n);
    if (k + 1 >= c.t.size()) { for (size_t i = 0; i < n; ++i) out[i] = c.q.back()[i]; return; }
    const float span = c.t[k + 1] - c.t[k];
    const float u = span > 0.0f ? (t - c.t[k]) / span : 0.0f;
    for (size_t i = 0; i < n; ++i) out[i] = nlerp(c.q[k][i], c.q[k + 1][i], u);
}

void write_all(const Play& p) {
    for (size_t i = 0; i < p.joint.size(); ++i)
        if (p.joint[i] != nullptr) set_any(JOINT, p.joint[i], "set_LocalRotation", &p.target[i]);
}
} // namespace

void play(const std::string& gun_id, const char* event, int hands) {
    const auto gun = short_id(gun_id);
    const Clip* c = load(gun, event);
    if (c == nullptr) return;
    const bool use_l = c->left && (hands & LEFT) != 0, use_r = c->right && (hands & RIGHT) != 0;
    if (!use_l && !use_r) { LOGI("%s shellclip: %s %s moves no hand that was asked for: not played", TAG, gun.c_str(), event); return; }
    // a new clip on a hand replaces the one playing there (a both-hands play replaces both)
    for (size_t i = 0; i < g_plays.size();) {
        const Play& o = g_plays[i];
        if ((use_l && o.left) || (use_r && o.right)) g_plays.erase(g_plays.begin() + i); else ++i;
    }
    Play p;
    p.clip = c;
    p.what = gun + "_" + event + (use_l && use_r ? "" : use_l ? " (left half)" : " (right half)");
    p.t0 = now_s();
    p.left = use_l;
    p.right = use_r;
    p.joint.assign(c->names.size(), nullptr);
    p.found.assign(c->names.size(), Quat{0, 0, 0, 1});
    p.target.assign(c->names.size(), Quat{0, 0, 0, 1});
    g_plays.push_back(std::move(p));
    LOGI("%s shellclip: %s %s: the game's finger movement plays on the %s hand (%.2f s)", TAG, gun.c_str(), event,
         use_l && use_r ? "left and right" : use_l ? "left" : "right", c->t.back());
}

void pulse(const std::vector<std::wstring>& joints, float ax, float ay, float az, float deg, float sec, bool right) {
    static std::map<std::string, Clip> pulses;   // a frameless clip per joint set: names, length, hand
    std::string key;
    for (const auto& j : joints) key += std::string(j.begin(), j.end()) + ",";
    Clip& c = pulses[key];
    c.names = joints;
    c.t = {0.0f, sec > 0.01f ? sec : 0.01f};
    c.q.assign(2, std::vector<Quat>(joints.size(), Quat{0, 0, 0, 1}));
    c.left = !right; c.right = right; c.ok = true;
    for (size_t i = 0; i < g_plays.size();) {
        const Play& o = g_plays[i];
        if ((right && o.right) || (!right && o.left)) g_plays.erase(g_plays.begin() + i); else ++i;
    }
    Play p;
    p.clip = &c;
    p.what = "pulse " + key;
    p.t0 = now_s();
    p.left = !right; p.right = right;
    p.pulse = true;
    const float n = std::sqrt(ax * ax + ay * ay + az * az);
    p.axis = n > 1e-4f ? Vec3{ax / n, ay / n, az / n} : Vec3{0, 0, 1};
    p.deg = deg;
    p.joint.assign(joints.size(), nullptr);
    p.found.assign(joints.size(), Quat{0, 0, 0, 1});
    p.target.assign(joints.size(), Quat{0, 0, 0, 1});
    g_plays.push_back(std::move(p));
    LOGI("%s shellclip: %s: %.0f deg about (%.2f %.2f %.2f) and back over %.2f s", TAG, g_plays.back().what.c_str(), deg, ax, ay, az, c.t.back());
}

bool playing() { return !g_plays.empty(); }
bool playing_left() { for (const auto& p : g_plays) if (p.left) return true; return false; }
bool playing_right() { for (const auto& p : g_plays) if (p.right) return true; return false; }

void frame() {
    // 2026-11-05 (Tefa: "the fingers don't move at all, not even a little"): Hand Poser held the docked hand's saved pose over the
    // clip; it now reads this slot and lets go of that hand while a clip plays (hand-poser-vr hand_poser.lua)
    bridge::put(bridge::S_CLIP_PLAYING, (playing_left() ? 1.0f : 0.0f) + (playing_right() ? 2.0f : 0.0f));
    static float last_check = -1.0f;
    const float t = now_s();
    if (t - last_check < 0.25f) return;
    last_check = t;
    const auto p = data_dir() / "play.txt";
    std::ifstream f(p);
    std::string line;
    if (f && std::getline(f, line) && !line.empty()) {
        f.close();
        std::ofstream(p, std::ios::trunc).close();
        std::stringstream ss(line);
        std::string id, event;
        ss >> id >> event;
        if (event.empty()) event = "round_in";
        LOGI("%s shellclip: test play asked for %s %s", TAG, id.c_str(), event.c_str());
        play(id, event.c_str());
    }
}

void render_point() {
    if (g_plays.empty()) return;
    const auto& s = player::now();
    if (s.tf == nullptr) { g_plays.clear(); return; }
    if (s.tf != g_tf) { g_tf = s.tf; for (auto& p : g_plays) for (auto& j : p.joint) j = nullptr; }
    const float now = now_s();
    for (size_t pi = 0; pi < g_plays.size();) {
        Play& p = g_plays[pi];
        const Clip& c = *p.clip;
        const size_t n = c.names.size();
        for (size_t i = 0; i < n; ++i) {
            if (p.joint[i] != nullptr) continue;
            const bool l = c.names[i].rfind(L"L_", 0) == 0, r = c.names[i].rfind(L"R_", 0) == 0;
            if ((l && !p.left) || (r && !p.right)) continue;   // the other hand's joints stay untouched
            p.joint[i] = joint_by_name(g_tf, c.names[i].c_str());
        }
        const float t = now - p.t0;
        const float len = c.t.back();
        if (!p.have) {   // the pose the hand had when the event happened: blended in from, and back out to
            for (size_t i = 0; i < n; ++i) {
                Quat q{0, 0, 0, 1};
                if (p.joint[i] != nullptr && get_q(JOINT, p.joint[i], "get_LocalRotation", q)) p.found[i] = qnorm(q);
                else p.found[i] = q;
            }
            p.have = true;
        }
        if (p.pulse) {   // a pulse: no blend, the half sine starts and ends at the found pose
            if (t >= len) { LOGI("%s shellclip: %s finished", TAG, p.what.c_str()); for (size_t i = 0; i < n; ++i) p.target[i] = p.found[i]; write_all(p); g_plays.erase(g_plays.begin() + pi); continue; }
            const float h = p.deg * std::sin(3.14159265f * t / len) * 3.14159265f / 360.0f, sn = std::sin(h);
            const Quat turn = qnorm({p.axis.x * sn, p.axis.y * sn, p.axis.z * sn, std::cos(h)});
            for (size_t i = 0; i < n; ++i) p.target[i] = qnorm(qmul(p.found[i], turn));
            write_all(p);
            ++pi;
            continue;
        }
        if (t >= len + SHELLCLIP_BLEND_S) {   // done: the other finger code takes the hand back from the next frame
            LOGI("%s shellclip: %s finished", TAG, p.what.c_str());
            g_plays.erase(g_plays.begin() + pi);
            continue;
        }
        std::vector<Quat> pose;
        sample(c, std::fmin(t, len), pose);
        const float in = std::fmin(1.0f, t / SHELLCLIP_BLEND_S);
        const float out = t > len ? std::fmax(0.0f, 1.0f - (t - len) / SHELLCLIP_BLEND_S) : 1.0f;
        for (size_t i = 0; i < n; ++i) p.target[i] = nlerp(p.found[i], pose[i], ease(std::fmin(in, out)));
        write_all(p);
        ++pi;
    }
}

void begin_render() {
    for (const auto& p : g_plays) if (p.have) write_all(p);
}

} // namespace vn::shellclip
