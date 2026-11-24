// showspot.cpp -- see showspot.h
#include "showspot.h"
#include "bridge.h"
#include "joints.h"
#include "json_mini.h"
#include "player.h"
#include "settings.h"
#include "zones.h"
#include <windows.h>
#include <cmath>
#include <ctime>
#include <filesystem>
#include <map>
#include <string>

namespace vn::showspot {

using namespace vn::settings;
using joints::now_s;

namespace {
struct Place { Vec3 p{0, 0, 0}; Quat q{0, 0, 0, 1}; bool body = false; };

Shown g_shown[2];                        // [0] the left hand, [1] the right
std::string g_gun;                       // the gun show.json was written for (short id, "ri3008")
double g_file_t = -1.0;                  // the heartbeat in show.json (unix seconds)
std::filesystem::file_time_type g_mtime{};
float g_read_t = -10.0f, g_save_t = -10.0f;
bool g_loaded = false, g_dirty = false;
std::map<std::string, std::map<std::string, Place>> g_places;   // gun -> "l|6|0|0" -> where that hand really sat
std::string g_said;                      // the last log line about what is shown (logged on change only)

std::filesystem::path dir() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    return std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8";
}
std::string short_gun() {
    const std::string& id = player::now().weapon_id;
    const auto k = id.find('_');
    return k == std::string::npos ? id : id.substr(0, k);
}
std::string key_of(bool left, int spot, int area, int holster) {
    return std::string(left ? "l" : "r") + "|" + std::to_string(spot) + "|" + std::to_string(area) + "|" + std::to_string(holster);
}
// a holster, first aid, the map, or a free hand at the pouch sits by the body, not on the gun
bool by_body(int spot, int area, int holster) { return holster > 0 || (spot == 14 && area == 1); }

void clear_shown() { g_shown[0] = Shown{}; g_shown[1] = Shown{}; }

Shown hand_of(const json::Value* h) {
    Shown s;
    if (h == nullptr || h->kind != json::Value::OBJ) return s;
    auto num = [&](const char* k) { const auto* v = h->get(k); return v != nullptr && v->kind == json::Value::NUM ? (int)std::lround(v->n) : 0; };
    s.on = true; s.spot = num("spot"); s.area = num("area"); s.holster = num("holster");
    return s;
}

void say(const std::string& line) { if (line != g_said) { g_said = line; LOGI("%s showspot: %s", TAG, line.c_str()); } }

void read_show() {
    std::error_code ec;
    const auto p = dir() / "show.json";
    const auto mt = std::filesystem::last_write_time(p, ec);
    if (ec) { clear_shown(); return; }
    if (mt != g_mtime) {
        g_mtime = mt;
        json::Value v;
        if (!json::load_file(p.wstring(), v) || v.kind != json::Value::OBJ) return;   // half-written: next time
        const auto* t = v.get("t");
        const auto* g = v.get("gun");
        g_file_t = t != nullptr && t->kind == json::Value::NUM ? t->n : -1.0;
        g_gun = g != nullptr && g->kind == json::Value::STR ? g->s : std::string();
        g_shown[0] = hand_of(v.get("left"));
        g_shown[1] = hand_of(v.get("right"));
    }
    const double age = (double)std::time(nullptr) - g_file_t;
    const bool any = g_shown[0].on || g_shown[1].on;
    if (any && (age > SHOW_STALE_S || age < -SHOW_STALE_S)) { clear_shown(); say("off (Hand Poser stopped asking)"); return; }
    if (any && g_gun != short_gun()) { clear_shown(); say("off (another gun in hand)"); return; }
    if (!any) say("off");
}

// ---- the recorded places ----
void load_places() {
    g_loaded = true;
    json::Value v;
    if (!json::load_file((dir() / "show_places.json").wstring(), v) || v.kind != json::Value::OBJ) return;
    for (const auto& [gun, spots] : v.obj) {
        if (spots.kind != json::Value::OBJ) continue;
        for (const auto& [k, a] : spots.obj) {
            if (a.kind != json::Value::ARR || a.arr.size() < 8) continue;
            auto n = [&](size_t i) { return a.arr[i].kind == json::Value::NUM ? (float)a.arr[i].n : 0.0f; };
            Place pl;
            pl.p = {n(0), n(1), n(2)};
            pl.q = qnorm(Quat{n(3), n(4), n(5), n(6)});
            pl.body = a.arr[7].kind == json::Value::STR && a.arr[7].s == "body";
            g_places[gun][k] = pl;
        }
    }
}
void save_places() {
    g_dirty = false;
    std::error_code ec;
    std::filesystem::create_directories(dir(), ec);
    const auto tmp = dir() / "show_places.json.tmp";
    FILE* f = _wfopen(tmp.wstring().c_str(), L"wb");
    if (f == nullptr) return;
    std::fprintf(f, "{");
    bool fg = true;
    for (const auto& [gun, spots] : g_places) {
        std::fprintf(f, "%s\n\"%s\":{", fg ? "" : ",", gun.c_str());
        fg = false;
        bool fs = true;
        for (const auto& [k, pl] : spots) {
            std::fprintf(f, "%s\"%s\":[%.5f,%.5f,%.5f,%.6f,%.6f,%.6f,%.6f,\"%s\"]", fs ? "" : ",", k.c_str(), pl.p.x, pl.p.y, pl.p.z,
                         pl.q.x, pl.q.y, pl.q.z, pl.q.w, pl.body ? "body" : "gun");
            fs = false;
        }
        std::fprintf(f, "}");
    }
    std::fprintf(f, "\n}\n");
    std::fclose(f);
    std::filesystem::rename(tmp, dir() / "show_places.json", ec);
}

// the frame a place is kept in: the gun's (its transform, as the arm sees it this frame) or the body's
bool frame_of(bool body, Vec3& p, Quat& q) {
    const auto& s = player::now();
    MO* tf = body ? s.tf : s.weapon_tf;
    if (tf == nullptr || !player::get_pose(tf, p, q)) return false;
    q = qnorm(q);
    return true;
}

// the zone a spot belongs to, for a spot never recorded (shown at the zone's middle)
bool zone_of(bool left, const Shown& sh, zones::Key& k) {
    if (sh.area >= 10 && sh.area < 10 + zones::COUNT) { k = (zones::Key)(sh.area - 10); return true; }
    if (!left) return false;
    switch (sh.spot) {
        case 3: case 11: k = zones::PART; return true;
        case 4: case 13: case 16: case 17: case 18: case 19: k = zones::MAG; return true;
        case 5: case 10: k = zones::HANDLE; return true;
        case 6: k = zones::DRUM; return true;
        case 7: k = zones::INSERT; return true;
        case 8: case 12: k = zones::SLIDE_LEFT; return true;
        default: return false;
    }
}
} // namespace

void frame() {
    if (!g_loaded) load_places();
    const float t = now_s();
    if (t - g_read_t >= SHOW_READ_EVERY_S) { g_read_t = t; read_show(); }
    if (g_dirty && t - g_save_t >= SHOW_SAVE_EVERY_S) { g_save_t = t; save_places(); }
}

const Shown& shown(bool left) { return g_shown[left ? 0 : 1]; }

void on_ik(MO* ik) {
    const auto& s = player::now();
    const bool left = ik == s.ik_left;
    if (!left && ik != s.ik_right) return;
    if (s.weapon == nullptr) return;
    MO* target = field_obj(ik, "Target");
    Vec3 hp; Quat hq;
    if (target == nullptr || !player::get_pose(target, hp, hq)) return;
    const std::string gun = short_gun();
    const Shown& sh = g_shown[left ? 0 : 1];

    if (!sh.on) {   // the real hand: remember where it sits at a real spot
        auto slot = [](bridge::Slot sl) { const float v = bridge::view(sl); return bridge::has(v) ? (int)std::lround(v) : 0; };
        const int spot = slot(left ? bridge::S_LEFT_SPOT : bridge::S_RIGHT_SPOT);
        const int area = slot(left ? bridge::S_LEFT_AREA : bridge::S_RIGHT_AREA);
        const int holster = slot(left ? bridge::S_LEFT_HOLSTER : bridge::S_RIGHT_HOLSTER);
        const bool real_spot = left ? ((spot != 0 && spot != 15) || holster > 0) : (spot > 0 || area > 0 || holster > 0);
        if (!real_spot) return;
        const bool body = by_body(spot, area, holster);
        Vec3 fp; Quat fq;
        if (!frame_of(body, fp, fq)) return;
        const Quat inv = qinv(fq);
        Place pl;
        pl.p = rotate(inv, hp - fp);
        pl.q = qnorm(qmul(inv, qnorm(hq)));
        pl.body = body;
        Place& old = g_places[gun][key_of(left, spot, area, holster)];
        if (old.body == body && dist(old.p, pl.p) < SHOW_MOVE_REC_M && std::fabs(old.q.w - pl.q.w) < 0.001f && (old.p.x != 0 || old.p.y != 0 || old.p.z != 0)) return;
        old = pl;
        g_dirty = true;
        return;
    }

    // SHOW: put the hand where it really sat there, else at the zone's middle
    const auto gi = g_places.find(gun);
    const std::string k = key_of(left, sh.spot, sh.area, sh.holster);
    if (gi != g_places.end()) {
        const auto pi = gi->second.find(k);
        if (pi != gi->second.end()) {
            Vec3 fp; Quat fq;
            if (!frame_of(pi->second.body, fp, fq)) return;
            player::set_pose(target, fp + rotate(fq, pi->second.p), qnorm(qmul(fq, pi->second.q)));
            say(std::string(left ? "left" : "right") + " hand shown at " + k + " (recorded)");
            return;
        }
    }
    zones::Key zk;
    Vec3 c;
    if (zone_of(left, sh, zk) && zones::shown_center(zk, c)) {
        player::set_pose(target, c, hq);   // the hand keeps its turn; only its place moves
        say(std::string(left ? "left" : "right") + " hand shown at " + k + " (zone middle: not recorded yet)");
        return;
    }
    say(std::string(left ? "left" : "right") + " hand at " + k + ": never recorded and no zone, the hand stays where it is (pose only)");
}

} // namespace vn::showspot
