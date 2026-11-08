// shellclip.cpp -- see shellclip.h. (2026-11-02; every gun, both hands, named events 2026-11-04; edits, nudges, hold 2026-11-07)
#include "shellclip.h"

#include <windows.h>

#include <algorithm>
#include <array>
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
#include "json_mini.h"
#include "player.h"
#include "settings.h"
#include "timings.h"

namespace vn::shellclip {

using namespace joints;
using namespace vn::settings;

namespace {
// 2026-11-07 (Animation & Timing): a clip's frames can be edited without touching the game's CSV: <gun>_<event>.edit.json holds
//   "ops"    applied in order to the frame list as it stands: {"op":"remove","i":k} drops edited frame k; {"op":"hold","i":k,"n":2}
//            repeats it n more times; {"op":"speed","from":a,"to":b,"x":0.5} makes frames a..b take 1/x the time (0.5 = twice as slow)
//   "nudges" [{"src":s, "joints":{"L_Thumb1":[dx,dy,dz] degrees...}, "hand":[x,y,z (cm), rx,ry,rz (deg)]}]: a turn on top of the clip's
//            own pose, and a move of the whole hand on the gun, keyed by the SOURCE frame (the CSV row), so they survive the ops.
//            Between keyed frames they interpolate along the edited time; flat before the first and after the last.
struct Frame { int src; float dt; };          // an edited frame: which CSV row, and how long it lasts
struct Clip {
    std::vector<std::wstring> names;          // the joints it moves, from the header (L_IndexF1 ... R_Thumb3)
    std::vector<std::vector<Quat>> raw;       // the CSV rows, one Quat per name
    std::vector<float> raw_t;
    std::vector<Frame> frames;                // after the ops
    std::vector<float> t;                     // each edited frame's start time
    std::vector<std::vector<Vec3>> nd;        // per edited frame, per name: the nudge in degrees (0 = none)
    std::vector<std::array<float, 6>> hand;   // per edited frame: the whole-hand move (m, deg), 0 = none
    bool any_nudge = false, any_hand = false;
    std::map<std::string, std::map<int, float>> part_keys;   // 2026-11-08: part name -> source row -> progress (shellclip.h part())
    bool ok = false, left = false, right = false;
    std::string key;
    std::filesystem::file_time_type csv_mt{}, edit_mt{};
    bool edit_exists = false;
    float next_check = 0.0f;
};
std::map<std::string, Clip> g_clips;          // "<gun>_<event>"; a missing file is remembered as not ok

struct Play {
    const Clip* clip = nullptr;
    std::string what;                         // "<gun>_<event>", for the log
    std::string key, event;
    float t0 = 0.0f;                          // when it started (now_s)
    std::vector<MO*> joint;
    std::vector<Quat> found, target;          // the pose at the start (blended in from / out to), and what is written
    bool have = false;
    bool left = false, right = false;         // the hands this play moves (the clip's, limited by play()'s hands)
    bool relative = false;                    // played on top of the found pose (g_relative at the start)
    bool pulse = false;                       // a pulse (pulse()): found * turn(axis, deg * sin), no clip frames
    Vec3 axis{0, 0, 1};
    float deg = 0.0f;
    // 2026-11-07: HELD on one edited frame by the Animation & Timing window (scrub.json): no clock, the frame it says
    bool held = false;
    int held_frame = 0;
    float release_t = -1.0f;                  // the hold let go: blends out from here
    float blend = 0.0f;                       // how much of the clip is on the hand right now (0..1), for hand_nudge()
    std::array<float, 6> hand_now{};          // this frame's whole-hand move, scaled by blend
    float frame_now = 0.0f;                   // the edited frame being shown (fractional while playing)
    float time_now = 0.0f;                    // 2026-11-08: the edited time being shown (for part())
    std::string tag;                          // 2026-11-08: who started it (play()'s tag), for part()
};
std::vector<Play> g_plays;
std::map<std::string, std::vector<std::string>> g_declared;   // 2026-11-08: "<gun>_<event>" -> the parts that move with it
bool g_relative = false;                      // relative.txt exists: clips play on top of the hand's own pose (shellclip.h)
MO* g_tf = nullptr;
int g_scrub_seq = -1;
float g_state_t = -10.0f;

std::filesystem::path data_dir() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    return std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "clips";
}

std::string short_id(const std::string& id) {
    const auto k = id.find('_');
    return k == std::string::npos ? id : id.substr(0, k);
}

float blend_s() { return std::fmax(0.01f, timings::v(timings::CLIP_BLEND_S)); }

// a turn from Euler degrees in the engine's own order (YXZ: measured 2026-11-05, dossier section 7)
Quat euler_yxz(const Vec3& deg) {
    const float d = 3.14159265f / 360.0f;
    const Quat qy{0, std::sin(deg.y * d), 0, std::cos(deg.y * d)}, qx{std::sin(deg.x * d), 0, 0, std::cos(deg.x * d)}, qz{0, 0, std::sin(deg.z * d), std::cos(deg.z * d)};
    return qnorm(qmul(qmul(qy, qx), qz));
}
bool zero3(const Vec3& v) { return std::fabs(v.x) + std::fabs(v.y) + std::fabs(v.z) < 1e-4f; }
bool zero6(const std::array<float, 6>& h) { float s = 0; for (float x : h) s += std::fabs(x); return s < 1e-6f; }

bool read_csv(Clip& c) {
    std::ifstream f(data_dir() / (c.key + ".csv"));
    if (!f) return false;
    c.names.clear(); c.raw.clear(); c.raw_t.clear(); c.left = c.right = false;
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
        c.raw_t.push_back(v[0]);
        std::vector<Quat> q(n);
        for (size_t i = 0; i < n; ++i) q[i] = qnorm({v[1 + i * 4], v[2 + i * 4], v[3 + i * 4], v[4 + i * 4]});
        c.raw.push_back(std::move(q));
    }
    return n > 0 && c.raw.size() >= 2;
}

// the edited frame list from the CSV rows and the ops, then the per-frame nudges (the same maths as the window's ClipModel.cs)
void apply_edits(Clip& c, const json::Value* edit) {
    const size_t n = c.names.size(), m = c.raw.size();
    c.frames.clear();
    for (size_t i = 0; i < m; ++i) {
        const float dt = i + 1 < m ? c.raw_t[i + 1] - c.raw_t[i] : (i > 0 ? c.raw_t[i] - c.raw_t[i - 1] : 1.0f / 60.0f);
        c.frames.push_back({(int)i, std::fmax(0.0f, dt)});
    }
    int nops = 0;
    if (const auto* ops = edit ? edit->get("ops") : nullptr; ops != nullptr && ops->kind == json::Value::ARR) {
        for (const auto& o : ops->arr) {
            const auto* op = o.get("op");
            if (op == nullptr || op->kind != json::Value::STR) continue;
            auto num = [&](const char* k, int d) { const auto* x = o.get(k); return x != nullptr && x->kind == json::Value::NUM ? (int)x->n : d; };
            const int cnt = (int)c.frames.size();
            if (op->s == "remove") {
                const int i = num("i", -1);
                if (i >= 0 && i < cnt && cnt > 2) { c.frames.erase(c.frames.begin() + i); ++nops; }
            } else if (op->s == "hold") {
                const int i = num("i", -1), k = std::clamp(num("n", 1), 1, 600);
                if (i >= 0 && i < cnt) { c.frames.insert(c.frames.begin() + i + 1, (size_t)k, c.frames[i]); ++nops; }
            } else if (op->s == "speed") {
                const int a = std::clamp(num("from", 0), 0, cnt - 1), b = std::clamp(num("to", cnt - 1), a, cnt - 1);
                const auto* xv = o.get("x");
                const float x = xv != nullptr && xv->kind == json::Value::NUM ? (float)xv->n : 1.0f;
                if (x > 0.01f) { for (int i = a; i <= b; ++i) c.frames[i].dt /= x; ++nops; }
            }
        }
    }
    c.t.assign(c.frames.size(), 0.0f);
    for (size_t k = 1; k < c.frames.size(); ++k) c.t[k] = c.t[k - 1] + c.frames[k - 1].dt;
    // the nudges: keyed by source row; every edited frame showing that row gets the key, the rest interpolate along the edited time
    struct KeyN { bool has = false; std::vector<Vec3> j; bool has_hand = false; std::array<float, 6> hand{}; };
    std::map<int, KeyN> keys;
    int nkeys = 0;
    c.part_keys.clear();
    if (const auto* nd = edit ? edit->get("nudges") : nullptr; nd != nullptr && nd->kind == json::Value::ARR) {
        for (const auto& e : nd->arr) {
            const auto* sv = e.get("src");
            if (sv == nullptr || sv->kind != json::Value::NUM) continue;
            KeyN& k = keys[(int)sv->n];
            k.has = true; ++nkeys;
            k.j.assign(n, Vec3{0, 0, 0});
            if (const auto* js = e.get("joints"); js != nullptr && js->kind == json::Value::OBJ)
                for (const auto& [name, a] : js->obj) {
                    if (a.kind != json::Value::ARR || a.arr.size() != 3) continue;
                    const std::wstring w = widen(name.c_str());
                    for (size_t i = 0; i < n; ++i) if (c.names[i] == w) k.j[i] = Vec3{(float)a.arr[0].n, (float)a.arr[1].n, (float)a.arr[2].n};
                }
            if (const auto* h = e.get("hand"); h != nullptr && h->kind == json::Value::ARR && h->arr.size() == 6) {
                k.has_hand = true;
                for (int i = 0; i < 6; ++i) k.hand[i] = (float)h->arr[i].n * (i < 3 ? 0.01f : 1.0f);   // cm -> m
            }
            if (const auto* ps = e.get("parts"); ps != nullptr && ps->kind == json::Value::OBJ)
                for (const auto& [name, x] : ps->obj) if (x.kind == json::Value::NUM) c.part_keys[name][(int)sv->n] = (float)x.n;
        }
    }
    const size_t f = c.frames.size();
    c.nd.assign(f, std::vector<Vec3>(n, Vec3{0, 0, 0}));
    c.hand.assign(f, std::array<float, 6>{});
    c.any_nudge = c.any_hand = false;
    if (nkeys > 0) {
        std::vector<int> keyed;   // edited frames that carry a key
        for (size_t k = 0; k < f; ++k) if (keys.count(c.frames[k].src)) keyed.push_back((int)k);
        for (size_t k = 0; k < f; ++k) {
            // the keyed frames just before and after (or at) k
            int lo = -1, hi = -1;
            for (int kk : keyed) { if (kk <= (int)k) lo = kk; if (kk >= (int)k && hi < 0) hi = kk; }
            if (lo < 0) lo = hi;
            if (hi < 0) hi = lo;
            const KeyN& a = keys[c.frames[lo].src];
            const KeyN& b = keys[c.frames[hi].src];
            const float span = c.t[hi] - c.t[lo];
            const float u = (hi == lo || span <= 0.0f) ? 0.0f : std::clamp((c.t[k] - c.t[lo]) / span, 0.0f, 1.0f);
            for (size_t i = 0; i < n; ++i) {
                c.nd[k][i] = Vec3{a.j[i].x + (b.j[i].x - a.j[i].x) * u, a.j[i].y + (b.j[i].y - a.j[i].y) * u, a.j[i].z + (b.j[i].z - a.j[i].z) * u};
                if (!zero3(c.nd[k][i])) c.any_nudge = true;
            }
            const std::array<float, 6> ha = a.has_hand ? a.hand : (b.has_hand ? b.hand : std::array<float, 6>{});
            const std::array<float, 6> hb = b.has_hand ? b.hand : ha;
            for (int i = 0; i < 6; ++i) c.hand[k][i] = ha[i] + (hb[i] - ha[i]) * u;
            if (!zero6(c.hand[k])) c.any_hand = true;
        }
    }
    std::string parts;
    for (const auto& [name, ks] : c.part_keys) parts += ", " + name + " keyed on " + std::to_string(ks.size()) + " row(s)";
    LOGI("%s shellclip: clip %s: %d CSV frames -> %d edited (%d op(s)), %d nudge key(s)%s%s%s, %.2f s", TAG, c.key.c_str(), (int)m, (int)f, nops, nkeys,
         c.any_nudge ? ", finger nudges" : "", c.any_hand ? ", whole-hand moves" : "", parts.c_str(), f > 0 ? c.t.back() : 0.0f);
}

// 2026-11-08: a part's progress at edited time `time` (shellclip.h part(); the same rule as the window's ClipMath.PartAt): the
// keyed frames' values along the edited time, 0 at the first frame and 1 at the last where those carry no key, straight between
float part_at(const Clip& c, const std::string& part, float time) {
    const size_t f = c.frames.size();
    if (f == 0) return 0.0f;
    std::vector<std::pair<float, float>> pts;   // (time, value), in frame order
    const auto it = c.part_keys.find(part);
    const std::map<int, float>* kv = it == c.part_keys.end() ? nullptr : &it->second;
    for (size_t k = 0; k < f; ++k) {
        const auto hit = kv != nullptr ? kv->find(c.frames[k].src) : std::map<int, float>::const_iterator{};
        if (kv != nullptr && hit != kv->end()) pts.push_back({c.t[k], hit->second});
        else if (k == 0) pts.push_back({c.t[0], 0.0f});
        else if (k == f - 1) pts.push_back({c.t[k], 1.0f});
    }
    if (time <= pts.front().first) return pts.front().second;
    for (size_t i = 1; i < pts.size(); ++i) {
        if (time > pts[i].first) continue;
        const float span = pts[i].first - pts[i - 1].first;
        const float u = span > 0.0f ? (time - pts[i - 1].first) / span : 1.0f;
        return pts[i - 1].second + (pts[i].second - pts[i - 1].second) * u;
    }
    return pts.back().second;
}

// (re)load the CSV and its edit file when either changed; false = no usable clip
bool refresh(Clip& c, bool force) {
    const float now = now_s();
    if (!force && now < c.next_check) return c.ok;
    c.next_check = now + 0.25f;
    std::error_code ec;
    const auto csv = data_dir() / (c.key + ".csv"), ed = data_dir() / (c.key + ".edit.json");
    const auto cmt = std::filesystem::last_write_time(csv, ec);
    if (ec) { if (c.ok || force) LOGI("%s shellclip: no clip %s (clips/%s.csv): the fingers stay as they are", TAG, c.key.c_str(), c.key.c_str()); c.ok = false; return false; }
    std::error_code ec2;
    const bool ex = std::filesystem::exists(ed, ec2);
    const auto emt = ex ? std::filesystem::last_write_time(ed, ec2) : std::filesystem::file_time_type{};
    const bool csv_new = cmt != c.csv_mt, edit_new = ex != c.edit_exists || (ex && emt != c.edit_mt);
    if (!force && !csv_new && !edit_new) return c.ok;
    json::Value edit;
    if (ex && !json::load_file(ed.wstring(), edit)) return c.ok;   // caught mid-write: the next check reads it
    if (csv_new || !c.ok) {
        if (!read_csv(c)) { c.ok = false; LOGI("%s shellclip: clip %s UNUSABLE (no joints or fewer than 2 frames)", TAG, c.key.c_str()); return false; }
        c.csv_mt = cmt;
    }
    c.edit_exists = ex; c.edit_mt = emt;
    apply_edits(c, ex ? &edit : nullptr);
    c.ok = c.frames.size() >= 2 && (c.left || c.right);
    return c.ok;
}

const Clip* load(const std::string& gun, const std::string& event) {
    const std::string key = gun + "_" + event;
    auto it = g_clips.find(key);
    const bool fresh = it == g_clips.end();
    Clip& c = g_clips[key];
    if (fresh) c.key = key;
    refresh(c, fresh);
    return c.ok ? &c : nullptr;
}

Quat nlerp(Quat a, Quat b, float u) {
    if (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w < 0.0f) b = {-b.x, -b.y, -b.z, -b.w};
    return qnorm({a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, a.z + (b.z - a.z) * u, a.w + (b.w - a.w) * u});
}

// the clip's pose between edited frames k and k+1 (u along), nudges on top; hand = the whole-hand move there
void pose_at(const Clip& c, size_t k, float u, std::vector<Quat>& out, std::array<float, 6>& hand) {
    const size_t n = c.names.size(), f = c.frames.size();
    out.resize(n);
    const size_t k2 = std::min(k + 1, f - 1);
    for (size_t i = 0; i < n; ++i) {
        Quat q = nlerp(c.raw[c.frames[k].src][i], c.raw[c.frames[k2].src][i], u);
        if (c.any_nudge) {
            const Vec3& a = c.nd[k][i];
            const Vec3& b = c.nd[k2][i];
            const Vec3 d{a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, a.z + (b.z - a.z) * u};
            if (!zero3(d)) q = qnorm(qmul(q, euler_yxz(d)));
        }
        out[i] = q;
    }
    for (int i = 0; i < 6; ++i) hand[i] = c.any_hand ? c.hand[k][i] + (c.hand[k2][i] - c.hand[k][i]) * u : 0.0f;
}

// the clip's pose at time t (linear between edited frames); frame_out = the fractional edited frame
void sample(const Clip& c, float t, std::vector<Quat>& out, std::array<float, 6>& hand, float& frame_out) {
    size_t k = 0;
    while (k + 1 < c.t.size() && c.t[k + 1] <= t) ++k;
    if (k + 1 >= c.t.size()) { pose_at(c, c.t.size() - 1, 0.0f, out, hand); frame_out = (float)(c.t.size() - 1); return; }
    const float span = c.t[k + 1] - c.t[k];
    const float u = span > 0.0f ? std::clamp((t - c.t[k]) / span, 0.0f, 1.0f) : 0.0f;
    pose_at(c, k, u, out, hand);
    frame_out = (float)k + u;
}

void write_all(const Play& p) {
    for (size_t i = 0; i < p.joint.size(); ++i)
        if (p.joint[i] != nullptr) set_any(JOINT, p.joint[i], "set_LocalRotation", &p.target[i]);
}

Play* play_on(const std::string& key, bool left) {   // the play of this clip on that hand, if any
    for (auto& p : g_plays) if (p.key == key && !p.pulse && (left ? p.left : p.right)) return &p;
    return nullptr;
}

void drop_hands(bool use_l, bool use_r) {   // a new clip on a hand replaces the one playing there (a both-hands play replaces both)
    for (size_t i = 0; i < g_plays.size();) {
        const Play& o = g_plays[i];
        if ((use_l && o.left) || (use_r && o.right)) g_plays.erase(g_plays.begin() + i); else ++i;
    }
}

bool start(const std::string& gun, const char* event, int hands, bool held, int frame, const char* why, const char* tag = nullptr) {
    const Clip* c = load(gun, event);
    if (c == nullptr) return false;
    const bool use_l = c->left && (hands & LEFT) != 0, use_r = c->right && (hands & RIGHT) != 0;
    if (!use_l && !use_r) { LOGI("%s shellclip: %s %s moves no hand that was asked for: not played", TAG, gun.c_str(), event); return false; }
    drop_hands(use_l, use_r);
    Play p;
    p.clip = c;
    p.key = c->key; p.event = event;
    p.what = gun + "_" + event + (use_l && use_r ? "" : use_l ? " (left half)" : " (right half)");
    p.t0 = now_s();
    p.left = use_l;
    p.right = use_r;
    p.relative = g_relative;
    p.held = held;
    p.tag = tag != nullptr ? tag : "";
    p.held_frame = std::clamp(frame, 0, (int)c->frames.size() - 1);
    p.joint.assign(c->names.size(), nullptr);
    p.found.assign(c->names.size(), Quat{0, 0, 0, 1});
    p.target.assign(c->names.size(), Quat{0, 0, 0, 1});
    g_plays.push_back(std::move(p));
    if (held) LOGI("%s shellclip: %s %s HELD on edited frame %d of %d on the %s hand (%s)", TAG, gun.c_str(), event, frame, (int)c->frames.size(), use_l && use_r ? "left and right" : use_l ? "left" : "right", why);
    else LOGI("%s shellclip: %s %s: the game's finger movement plays on the %s hand (%.2f s, %s; %s)", TAG, gun.c_str(), event,
              use_l && use_r ? "left and right" : use_l ? "left" : "right", c->t.back(), g_relative ? "on top of the hand's own pose" : "blended from the hand's pose", why);
    return true;
}

// 2026-11-07: the Animation & Timing window's scrub.json: {"seq":n, "gun":"ri3008", "event":"round_in", "hands":1|2|3, "frame":k, "hold":true}
// hold = keep edited frame k on the hand(s) until the next seq says otherwise; hold false with frame -1 = play it once; hold false
// with a held play on = let the hold go (blends out)
void poll_scrub() {
    const auto p = data_dir() / "scrub.json";
    json::Value v;
    if (!json::load_file(p.wstring(), v) || v.kind != json::Value::OBJ) return;
    const auto* sq = v.get("seq");
    if (sq == nullptr || sq->kind != json::Value::NUM || (int)sq->n == g_scrub_seq) return;
    g_scrub_seq = (int)sq->n;
    auto str = [&](const char* k) { const auto* x = v.get(k); return x != nullptr && x->kind == json::Value::STR ? x->s : std::string(); };
    auto num = [&](const char* k, int d) { const auto* x = v.get(k); return x != nullptr && x->kind == json::Value::NUM ? (int)x->n : d; };
    const auto* hv = v.get("hold");
    const bool hold = hv != nullptr && hv->kind == json::Value::BOOL && hv->b;
    const std::string gun = short_id(str("gun")), event = str("event");
    const int hands = std::clamp(num("hands", BOTH), 1, 3), frame = num("frame", -1);
    if (gun.empty() || event.empty()) return;
    const std::string key = gun + "_" + event;
    if (hold) {
        Play* pl = play_on(key, (hands & LEFT) != 0);
        if (pl == nullptr) pl = play_on(key, (hands & RIGHT) != 0);
        if (pl != nullptr && pl->held && pl->release_t < 0.0f) {   // the same hold: just another frame
            pl->held_frame = std::clamp(frame, 0, (int)pl->clip->frames.size() - 1);
            return;
        }
        start(gun, event.c_str(), hands, true, std::max(0, frame), "the window holds it");
        return;
    }
    bool any = false;
    for (auto& pl : g_plays) if (pl.key == key && pl.held && pl.release_t < 0.0f) { pl.release_t = now_s(); any = true; }
    if (any) { LOGI("%s shellclip: %s: the hold let go (blends out)", TAG, key.c_str()); return; }
    if (frame < 0) start(gun, event.c_str(), hands, false, 0, "the window asked for a play");
}

// twice a second: the gun's clips (edited frames, joints) and what plays, for the window
void write_state() {
    const auto& s = player::now();
    const std::string gun = short_id(s.weapon_id);
    std::error_code ec;
    std::filesystem::create_directories(data_dir(), ec);
    FILE* f = _wfopen((data_dir() / "clips_state.json").wstring().c_str(), L"wb");
    if (f == nullptr) return;
    std::fprintf(f, "{\"gun\":\"%s\",\"relative\":%s,\"clips\":[", gun.c_str(), g_relative ? "true" : "false");
    bool first = true;
    if (!gun.empty())
        for (const auto& e : std::filesystem::directory_iterator(data_dir(), ec)) {
            const auto name = e.path().filename().string();
            if (e.path().extension() != ".csv" || name.rfind(gun + "_", 0) != 0) continue;
            const std::string event = name.substr(gun.size() + 1, name.size() - gun.size() - 1 - 4);
            const Clip* c = load(gun, event);
            if (c == nullptr) continue;
            std::fprintf(f, "%s\n  {\"event\":\"%s\",\"hands\":\"%s\",\"csv_frames\":%d,\"frames\":%d,\"seconds\":%.4f,\"joints\":[", first ? "" : ",", event.c_str(),
                         c->left && c->right ? "both" : c->left ? "left" : "right", (int)c->raw.size(), (int)c->frames.size(), c->t.back());
            first = false;
            for (size_t i = 0; i < c->names.size(); ++i) std::fprintf(f, "%s\"%ls\"", i == 0 ? "" : ",", c->names[i].c_str());
            std::fputs("],\"raw_t\":[", f);
            for (size_t k = 0; k < c->raw_t.size(); ++k) std::fprintf(f, "%s%.4f", k == 0 ? "" : ",", c->raw_t[k]);
            std::fputs("],\"src\":[", f);
            for (size_t k = 0; k < c->frames.size(); ++k) std::fprintf(f, "%s%d", k == 0 ? "" : ",", c->frames[k].src);
            std::fputs("],\"t\":[", f);
            for (size_t k = 0; k < c->t.size(); ++k) std::fprintf(f, "%s%.4f", k == 0 ? "" : ",", c->t[k]);
            std::fputs("],\"parts\":[", f);   // 2026-11-08: the gun parts that move with it (declare_part, or keyed in its edit file)
            std::vector<std::string> parts;
            if (const auto d = g_declared.find(c->key); d != g_declared.end()) parts = d->second;
            for (const auto& [pn, ks] : c->part_keys) if (std::find(parts.begin(), parts.end(), pn) == parts.end()) parts.push_back(pn);
            for (size_t i = 0; i < parts.size(); ++i) std::fprintf(f, "%s\"%s\"", i == 0 ? "" : ",", parts[i].c_str());
            std::fputs("]}", f);
        }
    std::fputs("],\"playing\":[", f);
    first = true;
    for (const auto& p : g_plays) {
        if (p.pulse) continue;
        std::fprintf(f, "%s{\"event\":\"%s\",\"key\":\"%s\",\"hand\":\"%s\",\"frame\":%.2f,\"held\":%s,\"blend\":%.2f}", first ? "" : ",", p.event.c_str(), p.key.c_str(),
                     p.left && p.right ? "both" : p.left ? "left" : "right", p.frame_now, p.held && p.release_t < 0.0f ? "true" : "false", p.blend);
        first = false;
    }
    std::fputs("]}\n", f);
    std::fclose(f);
}
} // namespace

void play(const std::string& gun_id, const char* event, int hands, const char* tag) { start(short_id(gun_id), event, hands, false, 0, "the mod", tag); }

void declare_part(const std::string& gun_id, const char* event, const char* part) {
    auto& v = g_declared[short_id(gun_id) + "_" + event];
    if (std::find(v.begin(), v.end(), part) == v.end()) { v.push_back(part); LOGI("%s shellclip: %s %s moves the %s with it (its progress comes from the clip's frames)", TAG, short_id(gun_id).c_str(), event, part); }
}

bool part(const std::string& gun_id, const char* event, const char* part, const char* tag, float& u) {
    const std::string key = short_id(gun_id) + "_" + event;
    for (const auto& p : g_plays) {
        if (p.pulse || p.key != key || p.clip == nullptr || !p.have) continue;
        const bool window_hold = p.held && p.release_t < 0.0f;
        if (!window_hold && (p.held || tag == nullptr || p.tag != tag)) continue;   // a let-go hold, or someone else's play (RT's round)
        u = part_at(*p.clip, part, p.time_now);
        return true;
    }
    return false;
}

void pulse(const std::vector<std::wstring>& joints, float ax, float ay, float az, float deg, float sec, bool right) {
    static std::map<std::string, Clip> pulses;   // a frameless clip per joint set: names, length, hand
    std::string key;
    for (const auto& j : joints) key += std::string(j.begin(), j.end()) + ",";
    Clip& c = pulses[key];
    c.names = joints;
    c.t = {0.0f, sec > 0.01f ? sec : 0.01f};
    c.frames = {{0, c.t[1]}, {1, c.t[1]}};
    c.raw.assign(2, std::vector<Quat>(joints.size(), Quat{0, 0, 0, 1}));
    c.left = !right; c.right = right; c.ok = true;
    drop_hands(!right, right);
    Play p;
    p.clip = &c;
    p.what = "pulse " + key;
    p.key = p.what;
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

bool hand_nudge(bool left, float out[6]) {
    for (const auto& p : g_plays) {
        if (p.pulse || !p.have || (left ? !p.left : !p.right) || zero6(p.hand_now)) continue;
        for (int i = 0; i < 6; ++i) out[i] = p.hand_now[i];
        return true;
    }
    return false;
}

void frame() {
    // 2026-11-05 (Tefa: "the fingers don't move at all, not even a little"): Hand Poser held the docked hand's saved pose over the
    // clip; it now reads this slot and lets go of that hand while a clip plays (hand-poser-vr hand_poser.lua)
    bridge::put(bridge::S_CLIP_PLAYING, (playing_left() ? 1.0f : 0.0f) + (playing_right() ? 2.0f : 0.0f));
    static float last_check = -1.0f, last_scrub = -1.0f;
    const float t = now_s();
    if (t - last_scrub >= SHELLCLIP_SCRUB_POLL_S) { last_scrub = t; poll_scrub(); }
    for (auto& p : g_plays) if (p.held && p.clip != nullptr) refresh(g_clips[p.key], false);   // edits saved while a frame is held show at once
    if (t - g_state_t >= 0.5f) { g_state_t = t; write_state(); }
    if (t - last_check < 0.25f) return;
    last_check = t;
    {
        std::error_code ec;
        const bool rel = std::filesystem::exists(data_dir() / "relative.txt", ec);
        if (rel != g_relative) { g_relative = rel; LOGI("%s shellclip: clips now play %s", TAG, rel ? "ON TOP of the hand's own pose (relative.txt)" : "blended from the hand's pose (no relative.txt)"); }
    }
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
    const float bl = blend_s();
    for (size_t pi = 0; pi < g_plays.size();) {
        Play& p = g_plays[pi];
        const Clip& c = *p.clip;
        const size_t n = c.names.size();
        if (p.joint.size() != n) { LOGI("%s shellclip: %s: the clip's joints changed under it: stopped", TAG, p.what.c_str()); g_plays.erase(g_plays.begin() + pi); continue; }
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
        std::vector<Quat> pose;
        std::array<float, 6> hand{};
        float in, out;
        if (p.held) {   // one edited frame, as long as the window holds it; let go = blend out from there
            const size_t k = std::clamp((size_t)p.held_frame, (size_t)0, c.frames.size() - 1);
            pose_at(c, k, 0.0f, pose, hand);
            p.frame_now = (float)k;
            p.time_now = c.t[k];
            in = std::fmin(1.0f, t / bl);
            out = p.release_t < 0.0f ? 1.0f : std::fmax(0.0f, 1.0f - (now - p.release_t) / bl);
            if (p.release_t >= 0.0f && out <= 0.0f) { LOGI("%s shellclip: %s: hold over", TAG, p.what.c_str()); g_plays.erase(g_plays.begin() + pi); continue; }
        } else {
            if (t >= len + bl) {   // done: the other finger code takes the hand back from the next frame
                LOGI("%s shellclip: %s finished", TAG, p.what.c_str());
                g_plays.erase(g_plays.begin() + pi);
                continue;
            }
            sample(c, std::fmin(t, len), pose, hand, p.frame_now);
            p.time_now = std::fmin(t, len);
            in = std::fmin(1.0f, t / bl);
            out = t > len ? std::fmax(0.0f, 1.0f - (t - len) / bl) : 1.0f;
        }
        if (p.relative)   // the clip's change since its first frame, on top of the pose the hand had (shellclip.h)
            for (size_t i = 0; i < n; ++i) pose[i] = qnorm(qmul(p.found[i], qmul(qinv(c.raw[c.frames[0].src][i]), pose[i])));
        p.blend = ease(std::fmin(in, out));
        for (size_t i = 0; i < n; ++i) p.target[i] = nlerp(p.found[i], pose[i], p.blend);
        for (int i = 0; i < 6; ++i) p.hand_now[i] = hand[i] * p.blend;
        write_all(p);
        ++pi;
    }
}

void begin_render() {
    for (const auto& p : g_plays) if (p.have) write_all(p);
}

} // namespace vn::shellclip
