// smooth.cpp -- see smooth.h
#include "smooth.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "rack.h"
#include "reload.h"
#include "settings.h"
#include "json_mini.h"

#include <windows.h>

#include <filesystem>
#include <map>

namespace vn::smooth {

using namespace joints;
using namespace vn::settings;

namespace {
enum Owner : int { CONTROLLER = 0, GRIP = 1, RACK = 2, MAG = 3 };
const char* owner_name(int o) {
    return o == GRIP ? "the two-handed grip" : o == RACK ? "the slide / pump / bolt" : o == MAG ? "the magazine going in" : "the controller";
}

bool g_have = false;
int g_owner = CONTROLLER;
float g_t0 = -10.0f;
Vec3 g_off_p{};                    // the gap at the change, in the gun hand's frame
Quat g_off_q{0, 0, 0, 1};
Vec3 g_final_p{};                  // what was last drawn, in the gun hand's frame
Quat g_final_q{0, 0, 0, 1};
float g_frame = -1.0f;             // the game solves the arm twice a frame: the second solve gets the same answer
// 2026-10-24 (worn 15:39, Tefa: with the hand on the grip "hand jitters with handgun too while i walk, rifle does too"): the
// grip's place comes from the animation's socket, which the walk keeps moving. Once the hand has eased onto the grip, its place
// on the gun is frozen (in the gun hand's frame) until it lets go, so the walk cannot shake it
bool g_grip_frozen = false;
Vec3 g_grip_p{};
Quat g_grip_q{0, 0, 0, 1};

Quat slerp_from_identity(Quat q, float k) {   // identity -> q by k (0..1), the short way
    if (q.w < 0.0f) q = Quat{-q.x, -q.y, -q.z, -q.w};
    const float w = std::fmin(1.0f, q.w);
    const float a = std::acos(w);
    const float s = std::sin(a);
    if (s < 1e-5f) return Quat{0, 0, 0, 1};
    const float f = std::sin(k * a) / s;
    return qnorm(Quat{q.x * f, q.y * f, q.z * f, std::cos(k * a)});
}
MO* target_of(MO* ik) { return field_obj(ik, "Target"); }

// 2026-10-24 (Tefa's screenshots: "multiple spots where the hand can dock and which ever way"): the place frozen above was
// wherever the animation's socket stood when the hand settled, so every take differed. The grip script
// (lua/re8_vrz_begone_grip.lua) now keeps ONE spot per gun in data/visceral_re8/grip_spots.json (the game's aiming grip, or
// the wearer's own); while the hand is on the grip it is drawn THERE, in the gun hand's frame, eased onto as before.
struct Spot { Vec3 p; Quat q; };
std::map<int, Spot> g_spots;
float g_spots_t = -10.0f;
std::filesystem::file_time_type g_spots_mtime{};
std::filesystem::path spots_path() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    return std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "grip_spots.json";
}
void spots_refresh() {   // at most once a second: re-read the file when it changed
    const float t = now_s();
    if (t - g_spots_t < 1.0f) return;
    g_spots_t = t;
    std::error_code ec;
    const auto path = spots_path();
    const auto mt = std::filesystem::last_write_time(path, ec);
    if (ec) { if (!g_spots.empty()) { g_spots.clear(); LOGI("%s smooth: no kept grip spots (file gone)", TAG); } return; }
    if (mt == g_spots_mtime) return;
    g_spots_mtime = mt;
    json::Value v;
    if (!json::load_file(path.wstring(), v) || v.kind != json::Value::OBJ) return;
    g_spots.clear();
    for (const auto& [k, s] : v.obj) {
        auto num = [&](const char* n) { const auto* x = s.get(n); return x != nullptr && x->kind == json::Value::NUM ? (float)x->n : 0.0f; };
        if (s.get("x") == nullptr) continue;
        g_spots[std::atoi(k.c_str())] = Spot{{num("x"), num("y"), num("z")}, qnorm({num("qx"), num("qy"), num("qz"), num("qw")})};
    }
    LOGI("%s smooth: %d kept grip spot(s) read", TAG, (int)g_spots.size());
}
const Spot* spot_now() {
    const int n = (int)(bridge::view(bridge::S_WEAPON_NUM) + 0.5f);
    auto it = g_spots.find(n);
    return it == g_spots.end() ? nullptr : &it->second;
}
} // namespace

void on_ik(MO* ik) {
    const auto& s = player::now();
    if (ik != s.ik_left) return;
    if (bridge::experiment(bridge::EX_NO_SMOOTH) || !bridge::live()) { g_have = false; return; }
    Vec3 rp, lp;
    Quat rq, lq;
    if (!player::get_pose(target_of(s.ik_right), rp, rq) || !player::get_pose(target_of(ik), lp, lq)) return;
    const Quat inv = qinv(qnorm(rq));
    Vec3 rel = rotate(inv, lp - rp);
    Quat qrel = qnorm(qmul(inv, qnorm(lq)));
    const float frame = bridge::view(bridge::S_FRAME);
    // 2026-10-24 first wear: "there is a frame right after i press LG that already shows the hand docked". The scope's grip
    // script docks the hand in a LATER solve of the same frame, after this had decided the frame, and that solve drew the
    // dock unsmoothed. So a later solve asking for a place within a dock's reach of the first answer draws the first answer.
    // (Build 2 instead eased any ask that moved between solves: the later solves also ask for places 0.4-0.7 m away every
    // frame, so the free hand was dragged with the gun and lagged -- Tefa: "super janky". Those far asks are left alone
    // again, as in build 1, where nothing looked wrong with them.)
    // Build 5 (worn 13:49): that also held back the grip script's UNDO of the game's 10 cm dock (made without LG), so the
    // unwanted dock stayed on screen. A late ask that comes back toward the left controller is an undo: drawn as asked.
    if (g_have && frame == g_frame) {
        const bool easing = now_s() - g_t0 < SMOOTH_DOCK_SEC;
        Vec3 cp;
        const Vec3 first = rp + rotate(rq, g_final_p);
        // 2026-10-24 (Tefa: "when inserting the mag, left hand keeps rapidly going in the direction of the insertion and then
        // teleports back onto the mag"): while the hand is ours (slide / pump / bolt / magazine) the grip script's undo moved
        // it toward the controller in a later solve and that was drawn. Ours: the first answer always wins
        const bool ours = rack::active() || reload::hand_on_mag() || g_grip_frozen;
        // (worn 15:27, Tefa: gripping the handgun "hand jumps around a bit like fighting something", and walking with the rifle
        // gripped "the hand jitters a lot around the gripping area"): with LG held the grip is wanted, and the later solves'
        // pulls toward the controller were drawn every frame. An undo is only an undo with LG let go
        const bool lg = bridge::held(bridge::S_LGRIP);
        if (!ours && !lg && !easing && bridge::room_to_world(bridge::hand_pos(bridge::LEFT), cp) && dist(lp, cp) + SMOOTH_TOWARD_M < dist(first, cp)) {
            g_final_p = rel;
            g_final_q = qrel;
            return;
        }
        if (ours || easing || dist(rel, g_final_p) <= SMOOTH_LATE_DOCK_M) player::set_pose(target_of(ik), first, qnorm(qmul(rq, g_final_q)));
        return;
    }
    g_frame = frame;
    // 23:49 (Tefa: "the automatic docking is still present"): the game's own 10 cm dock (made without LG) counted as the grip
    // here and was eased onto, which also held back the grip script's undo; the grip is only the grip with LG held
    const bool lg_held = bridge::held(bridge::S_LGRIP);
    const int owner = rack::active() ? RACK : reload::hand_on_mag() ? MAG : (bridge::flag(bridge::S_GRIPPING_WEAPON) && lg_held) ? GRIP : CONTROLLER;
    spots_refresh();
    const Spot* kept = owner == GRIP ? spot_now() : nullptr;
    if (kept != nullptr) { rel = kept->p; qrel = kept->q; }
    if (!g_have) {
        g_have = true;
        g_owner = owner;
        g_final_p = rel;
        g_final_q = qrel;
        return;
    }
    if (owner != GRIP) g_grip_frozen = false;
    if (owner != g_owner) {
        g_off_p = g_final_p - rel;
        g_off_q = qnorm(qmul(g_final_q, qinv(qrel)));
        g_t0 = now_s();
        LOGI("%s smooth: left hand %s -> %s, eased over %.2f s (gap %.3f m)", TAG, owner_name(g_owner), owner_name(owner), SMOOTH_DOCK_SEC,
             dist(g_final_p, rel));
        g_owner = owner;
    }
    const float k = 1.0f - ease((now_s() - g_t0) / SMOOTH_DOCK_SEC);
    if (owner == GRIP && k <= 0.0f) {
        if (!g_grip_frozen || (kept != nullptr && (dist(g_grip_p, rel) > 0.001f))) {
            g_grip_frozen = true;
            g_grip_p = rel;
            g_grip_q = qrel;
            LOGI("%s smooth: the left hand's place on the grip frozen (%.3f %.3f %.3f in the gun hand's frame, %s)", TAG, rel.x, rel.y, rel.z,
                 kept != nullptr ? "this gun's kept spot" : "where it settled: no kept spot for this gun yet");
        }
        g_final_p = g_grip_p;
        g_final_q = g_grip_q;
        player::set_pose(target_of(ik), rp + rotate(rq, g_final_p), qnorm(qmul(rq, g_final_q)));
        return;
    }
    if (k <= 0.0f) {
        g_final_p = rel;
        g_final_q = qrel;
        return;
    }
    g_final_p = rel + g_off_p * k;
    g_final_q = qnorm(qmul(slerp_from_identity(g_off_q, k), qrel));
    player::set_pose(target_of(ik), rp + rotate(rq, g_final_p), qnorm(qmul(rq, g_final_q)));
}

} // namespace vn::smooth
