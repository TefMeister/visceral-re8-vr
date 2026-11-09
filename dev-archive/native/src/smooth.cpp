// smooth.cpp -- see smooth.h
#include "smooth.h"
#include "zones.h"
#include "bridge.h"
#include "joints.h"
#include "pairs.h"
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
enum Owner : int { CONTROLLER = 0, GRIP = 1, RACK = 2, MAG = 3, PAIR = 4 };
const char* owner_name(int o) {
    return o == GRIP ? "the two-handed grip" : o == RACK ? "the slide / pump / bolt" : o == MAG ? "the magazine going in" : o == PAIR ? "a hand pair's landing spot" : "the controller";
}

bool g_have = false;
int g_owner = CONTROLLER;
float g_t0 = -10.0f;
Vec3 g_off_p{};                    // the gap at the change, in the gun hand's frame
Quat g_off_q{0, 0, 0, 1};
Vec3 g_final_p{};                  // what was last drawn, in the gun hand's frame
Quat g_final_q{0, 0, 0, 1};
float g_frame = -1.0f;             // the game solves the arm twice a frame: the second solve gets the same answer
int g_glide_id = 0;                // b102: +1 at each owner change (glide_id())
// 2026-10-24 (worn 15:39, Tefa: with the hand on the grip "hand jitters with handgun too while i walk, rifle does too"): the
// grip's place comes from the animation's socket, which the walk keeps moving. Once the hand has eased onto the grip, its place
// on the gun is frozen (in the gun hand's frame) until it lets go, so the walk cannot shake it
bool g_grip_frozen = false;
Vec3 g_grip_p{};
Quat g_grip_q{0, 0, 0, 1};
// 2026-10-25 (Tefa: "to put the left hand on the racking bolt, it kind of goes through the back of the weapon a little and i would
// need to set it so it arches over the back of the gun, then grips the bolt handle"): the hand's ease onto (and off) the slide /
// pump / bolt went in a straight line in the gun hand's frame, so it cut through the gun. It now rises along the gun's up by
// up to the arc height (Grab Zones' HAND ON THE BOLT box, bridge S_ARC_CM) at the middle of the ease, and takes SMOOTH_ARC_SEC
float g_arc_m = 0.0f;
float g_ease_sec = SMOOTH_DOCK_SEC;
// 2026-11-08 (Tefa: "docking on the slide, Ethan's hand does like an arching movement with his hand, before landing on the slide
// and we need the hand to travel the shortest way to the docking point"): the arc is for the BOLT only now (where it was asked
// for, 2026-10-25), and the ease moves the PALM in a straight line: the target is the wrist, so easing the wrist straight while
// the hand turns swept the palm round in a curve. With no palm offset measured yet it is the wrist, as before.
Vec3 g_off_palm{};

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
// ---- THE FREE HAND STAYS ON ITS CONTROLLER (23:55, Tefa: "the automated docking area doesn't dock anymore but the hand pose
// teleport-changes when near it and moving my hand around, still like semi-docking at the handle not moving fully with the
// left controller, then snapping to the actual location"). praydog docks the hand within 10 cm of the animation's grip
// spot whatever the button, and the grip script's undo came in a later solve. Now, with LG up, the hand's place is
// predicted from the controller itself and written in the FIRST solve: the offset between the controller and praydog's
// free-hand target (his left-hand offsets) is learned while he has NOT docked, and a target further than
// FREE_DEVIATION_M from that prediction (a dock) is put back on it.
bool g_cal = false;
Vec3 g_cal_p{};
Quat g_cal_q{0, 0, 0, 1};
int g_free_frames = 0;
float g_free_frame = -1.0f;   // the frame the free hand was put back
Vec3 g_free_p{};
Quat g_free_q{0, 0, 0, 1};
int g_free_told = 0;
int g_free_count = 0;
float g_free_log_t = -10.0f;
// 03:50 (Tefa: the free hand "swings the whole arm around like the motion controller is the centre", some launches, not
// others; the log: 29 interaction-profile switches in 20 minutes, each after the controllers dropped out of tracking): the
// put-back used an offset learned over time, which a bad moment could poison. praydog's own offsets now come through the
// bridge each frame (slots 106-112), and the prediction is exactly his placement: controller + rotated position offset
// 2026-11-10 (Fable; Tefa 2026-11-09: "left hand is still jittery when on it's own"): the put-back above fired about once
// a frame for a whole 17-minute run (65,905 times) with the game's dock already off (nodock), so it is not catching docks:
// it is the prediction (a frame-start snapshot of the controller and the camera) disagreeing with praydog's own fresh
// placement, and the snapshot is what got drawn. The probe measures that gap per arm solve; the mode picks what is drawn:
//   0 = as before (put back whenever the target is FREE_DEVIATION_M from the prediction)
//   1 = put back only when praydog's own flag says he docked (was_gripping_weapon); otherwise his placement is drawn,
//       exactly as the right hand's is
// reframework/data/visceral_re8/freehand.json {"mode": 0|1} overrides FREE_PUTBACK_MODE, re-read once a second
int g_fh_mode = FREE_PUTBACK_MODE;
float g_fh_mode_t = -10.0f;
void fh_mode_refresh() {
    const float t = now_s();
    if (t - g_fh_mode_t < 1.0f) return;
    g_fh_mode_t = t;
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    json::Value v;
    int m = FREE_PUTBACK_MODE;
    if (json::load_file((std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "freehand.json").wstring(), v) && v.kind == json::Value::OBJ) {
        const auto* x = v.get("mode");
        if (x != nullptr && x->kind == json::Value::NUM) m = (int)x->n;
    }
    if (m != g_fh_mode) { g_fh_mode = m; LOGI("%s smooth: free-hand put-back mode %d (%s)", TAG, m, m == 1 ? "only when praydog says he docked" : "whenever the target leaves the prediction"); }
}
struct FhProbe { int n = 0, over = 0; float sum = 0.0f, mx = 0.0f; };
FhProbe g_fh[4];
int g_fh_solve = 0, g_fh_frames = 0, g_fh_flag_frames = 0, g_fh_putbacks = 0;
float g_fh_frame = -1.0f, g_fh_t = -10.0f, g_fh_step_sum = 0.0f, g_fh_step_max = 0.0f;
Vec3 g_fh_last_c{};
void fh_probe(float frame, float dev, Vec3 cp) {
    if (frame != g_fh_frame) {
        g_fh_frame = frame;
        g_fh_solve = 0;
        ++g_fh_frames;
        if (bridge::flag(bridge::S_GRIPPING_WEAPON)) ++g_fh_flag_frames;
        const float step = dist(cp, g_fh_last_c);
        g_fh_last_c = cp;
        if (step < 0.5f) { g_fh_step_sum += step; g_fh_step_max = std::fmax(g_fh_step_max, step); }
    }
    FhProbe& b = g_fh[g_fh_solve < 3 ? g_fh_solve : 3];
    ++g_fh_solve;
    ++b.n;
    b.sum += dev;
    b.mx = std::fmax(b.mx, dev);
    if (dev > FREE_DEVIATION_M) ++b.over;
    if (now_s() - g_fh_t < 2.0f) return;
    g_fh_t = now_s();
    if (g_fh_frames > 0)
        LOGI("%s freehand probe (mode %d): %d frames, praydog-docked flag on %d, put back %d; the predicted hand moved %.1f mm a frame (max %.1f); gap prediction-to-praydog in mm, mean/max/over-4cm per solve: #1 %.1f/%.1f/%d of %d, #2 %.1f/%.1f/%d of %d, #3 %.1f/%.1f/%d of %d, later %.1f/%.1f/%d of %d",
             TAG, g_fh_mode, g_fh_frames, g_fh_flag_frames, g_fh_putbacks, g_fh_step_sum / g_fh_frames * 1000.0f, g_fh_step_max * 1000.0f,
             g_fh[0].n ? g_fh[0].sum / g_fh[0].n * 1000.0f : 0.0f, g_fh[0].mx * 1000.0f, g_fh[0].over, g_fh[0].n,
             g_fh[1].n ? g_fh[1].sum / g_fh[1].n * 1000.0f : 0.0f, g_fh[1].mx * 1000.0f, g_fh[1].over, g_fh[1].n,
             g_fh[2].n ? g_fh[2].sum / g_fh[2].n * 1000.0f : 0.0f, g_fh[2].mx * 1000.0f, g_fh[2].over, g_fh[2].n,
             g_fh[3].n ? g_fh[3].sum / g_fh[3].n * 1000.0f : 0.0f, g_fh[3].mx * 1000.0f, g_fh[3].over, g_fh[3].n);
    for (auto& b2 : g_fh) b2 = FhProbe{};
    g_fh_frames = g_fh_flag_frames = g_fh_putbacks = 0;
    g_fh_step_sum = g_fh_step_max = 0.0f;
}
bool praydog_offsets(Vec3& p, Quat& q) {
    const float x = bridge::view(bridge::S_LHAND_OFF);
    if (!bridge::has(x)) return false;
    p = Vec3{x, bridge::view((bridge::Slot)(bridge::S_LHAND_OFF + 1)), bridge::view((bridge::Slot)(bridge::S_LHAND_OFF + 2))};
    q = qnorm(Quat{bridge::view(bridge::S_LHAND_ROT_OFF), bridge::view((bridge::Slot)(bridge::S_LHAND_ROT_OFF + 1)), bridge::view((bridge::Slot)(bridge::S_LHAND_ROT_OFF + 2)), bridge::view((bridge::Slot)(bridge::S_LHAND_ROT_OFF + 3))});
    return std::isfinite(p.x) && std::isfinite(q.w);
}
bool controller_now(Vec3& p, Quat& q) {
    if (!bridge::room_to_world(bridge::hand_pos(bridge::LEFT), p) || !bridge::room_rot_to_world(bridge::view_quat(bridge::S_LROT), q)) return false;
    q = qnorm(q);
    return std::isfinite(p.x) && std::isfinite(q.w);
}
Quat nlerp_q(Quat a, Quat b, float u) {
    if (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w < 0.0f) b = {-b.x, -b.y, -b.z, -b.w};
    return qnorm({a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, a.z + (b.z - a.z) * u, a.w + (b.w - a.w) * u});
}

const Spot* spot_now() {
    const int n = (int)(bridge::view(bridge::S_WEAPON_NUM) + 0.5f);
    auto it = g_spots.find(n);
    return it == g_spots.end() ? nullptr : &it->second;
}
} // namespace

// the FRONT GRIP zone (2026-10-25, Fable; Tefa: "the front part of the gun is missing from the list"): this gun's kept spot
// in the gun hand's frame, as a world point, moved by zones.json "grip" (in the gun's axes) and as big as the take distance.
// The grip script reads it back from the bridge and takes the grip inside it; no kept spot = no zone
void publish_zone() {
    spots_refresh();
    const auto& s = player::now();
    const Spot* kept = (bridge::live() && s.weapon != nullptr) ? spot_now() : nullptr;
    Vec3 rp;
    Quat rq;
    if (kept == nullptr || !player::get_pose(target_of(s.ik_right), rp, rq)) { zones::clear(zones::GRIP); return; }
    zones::publish(zones::GRIP, zones::center(zones::GRIP, rp + rotate(qnorm(rq), kept->p)), zones::radius(zones::GRIP));
}

bool easing() { return g_have && !bridge::experiment(bridge::EX_NO_SMOOTH) && now_s() - g_t0 < g_ease_sec; }
float progress() { return easing() ? ease((now_s() - g_t0) / g_ease_sec) : 1.0f; }
int glide_id() { return g_glide_id; }

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
    // 01:06 (live watch, Tefa hovering at the pump: the game's dock switched on and off four times in four seconds, "it also
    // just jumps forward close to the gun"): the dock was only caught in the FIRST solve of a frame; a dock in a later solve
    // fell through to the hold-back below, which is measured from the gun hand that the dock had just turned toward the
    // controller, so the hand followed the gun. Now every solve of a free hand (LG up) is checked against the controller
    const bool free_now = !bridge::held(bridge::S_LGRIP) && !rack::active() && !reload::hand_on_mag() && !bridge::flag(bridge::S_IS_RELOADING);
    {   // praydog's exact offsets replace whatever was learned, every frame
        Vec3 po;
        Quat ro;
        if (praydog_offsets(po, ro)) { g_cal = true; g_cal_p = po; g_cal_q = ro; }
    }
    if (free_now && g_cal) {
        Vec3 cp;
        Quat cq;
        if (controller_now(cp, cq)) {
            const Vec3 pp = cp + rotate(cq, g_cal_p);
            const Quat pq = qnorm(qmul(cq, g_cal_q));
            fh_mode_refresh();
            fh_probe(frame, dist(lp, pp), pp);
            const bool put_back = g_fh_mode == 1 ? (bridge::flag(bridge::S_GRIPPING_WEAPON) && dist(lp, pp) > FREE_DEVIATION_M) : dist(lp, pp) > FREE_DEVIATION_M;
            if (put_back) {
                ++g_fh_putbacks;
                player::set_pose(target_of(ik), pp, pq);
                g_free_frame = frame;
                g_free_p = pp;
                g_free_q = pq;
                ++g_free_count;
                if (now_s() - g_free_log_t > 1.0f) { g_free_log_t = now_s(); LOGI("%s smooth: the game docked the free hand (LG up): put back on the controller (%d times so far)", TAG, g_free_count); }
                if (g_have && frame == g_frame) {
                    // 2026-11-09 (Tefa: off the slide the hand "teleports"; b091 eased it over 0.40 s, but every later solve of the
                    // frame put the free hand straight back on the controller): during the way back, a later solve draws the eased place
                    if (g_owner == CONTROLLER && now_s() - g_t0 < g_ease_sec) player::set_pose(target_of(ik), rp + rotate(rq, g_final_p), qnorm(qmul(rq, g_final_q)));
                    return;
                }
                lp = pp;
                lq = pq;
                rel = rotate(inv, lp - rp);
                qrel = qnorm(qmul(inv, qnorm(lq)));
            }
        }
    }
    if (g_have && frame == g_frame) {
        if (g_free_frame == frame && free_now) {
            if (g_owner == CONTROLLER && now_s() - g_t0 < g_ease_sec) player::set_pose(target_of(ik), rp + rotate(rq, g_final_p), qnorm(qmul(rq, g_final_q)));   // 2026-11-09: still on the way back
            else player::set_pose(target_of(ik), g_free_p, g_free_q);   // a later solve's dock: the free hand stays put back
            return;
        }
        const bool easing = now_s() - g_t0 < g_ease_sec;
        Vec3 cp;
        const Vec3 first = rp + rotate(rq, g_final_p);
        // 2026-10-24 (Tefa: "when inserting the mag, left hand keeps rapidly going in the direction of the insertion and then
        // teleports back onto the mag"): while the hand is ours (slide / pump / bolt / magazine) the grip script's undo moved
        // it toward the controller in a later solve and that was drawn. Ours: the first answer always wins
        const bool ours = rack::active() || reload::hand_on_mag() || pairs::active() || g_grip_frozen;
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
    const int owner = rack::active() ? RACK : reload::hand_on_mag() ? MAG : pairs::active() ? PAIR : (bridge::flag(bridge::S_GRIPPING_WEAPON) && lg_held) ? GRIP : CONTROLLER;
    // the free hand (see "THE FREE HAND STAYS ON ITS CONTROLLER")
    if (owner == CONTROLLER && !lg_held && !bridge::flag(bridge::S_IS_RELOADING)) {
        Vec3 cp;
        Quat cq;
        if (controller_now(cp, cq)) {
            const Quat cinv = qinv(cq);
            const Vec3 pp = g_cal ? cp + rotate(cq, g_cal_p) : lp;
            const Quat pq = g_cal ? qnorm(qmul(cq, g_cal_q)) : lq;
            // 01:50 (Tefa: near the pump "the hand still rotates"): within a few cm of the dock spot the docked pose passed the
            // distance test and its ROTATION was learned, so the hand turned slowly toward the grip. A turn away from the
            // prediction now counts as a dock, and nothing is learned unless the hand is well away from the gun and the pouch
            const float turn_away = g_cal ? std::fabs(2.0f * std::acos(std::fmin(1.0f, std::fabs(lq.x * pq.x + lq.y * pq.y + lq.z * pq.z + lq.w * pq.w)))) : 0.0f;
            const bool docked = bridge::flag(bridge::S_GRIPPING_WEAPON) || (g_cal && (dist(lp, pp) > FREE_DEVIATION_M || turn_away > FREE_TURN_DEVIATION_RAD));
            const bool clean = !docked && rack::left_gun_closeness() <= 0.0f && !reload::in_pouch();
            if (!docked && !clean) { /* near the gun: neither learned nor put back */ }
            else if (clean) {
                const Vec3 np = rotate(cinv, lp - cp);
                const Quat nq = qnorm(qmul(cinv, qnorm(lq)));
                if (++g_free_frames >= FREE_LEARN_FRAMES && std::sqrt(np.x * np.x + np.y * np.y + np.z * np.z) < FREE_OFFSET_MAX_M) {
                    if (!g_cal) { g_cal = true; g_cal_p = np; g_cal_q = nq; LOGI("%s smooth: the free hand's controller offset learned (%.3f %.3f %.3f)", TAG, np.x, np.y, np.z); }
                    else { g_cal_p = g_cal_p + (np - g_cal_p) * FREE_LEARN_RATE; g_cal_q = nlerp_q(g_cal_q, nq, FREE_LEARN_RATE); }
                }
            } else if (g_cal) {
                g_free_frames = 0;   // (the put-back itself happened above, for every solve)
            }
        }
    } else {
        g_free_frames = 0;
    }
    spots_refresh();
    const Spot* kept = owner == GRIP ? spot_now() : nullptr;
    if (kept != nullptr) { rel = kept->p; qrel = kept->q; }
    // a hand pair (pairs.h, 2026-10-25): the hand goes to the pair's landing spot, riding the gun, with the turn it had at the take
    if (owner == PAIR) { Vec3 pp; Quat pq; if (pairs::landing(rp, rq, pp, pq)) { rel = pp; qrel = pq; } }
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
        {
            Vec3 t{};
            if (!rack::palm_offset(t)) t = Vec3{0, 0, 0};
            g_off_palm = (g_final_p + rotate(g_final_q, t)) - (rel + rotate(qrel, t));
        }
        g_t0 = now_s();
        ++g_glide_id;
        {
            const float a = bridge::view(bridge::S_ARC_CM);
            const bool rack_end = ((owner == RACK || g_owner == RACK) && rack::bolt_gun()) || owner == PAIR || g_owner == PAIR;   // (the pairs arc too; slides and pumps go straight, 2026-11-08)
            g_arc_m = (rack_end && bridge::has(a) && a > 0.0f) ? std::fmin(a * 0.01f, SMOOTH_ARC_MAX_M) : 0.0f;
            g_ease_sec = g_arc_m > 0.0f ? SMOOTH_ARC_SEC : SMOOTH_DOCK_SEC;
            // 2026-11-09 (Tefa: after the slide rack "hand must smoothly move to where my motion controller is, not teleport"): off a
            // part back to the controller goes slower than a dock, so the way back reads as a move
            if (g_arc_m <= 0.0f && g_owner == RACK && owner == CONTROLLER) g_ease_sec = SMOOTH_RELEASE_SEC;
        }
        LOGI("%s smooth: left hand %s -> %s, eased over %.2f s (gap %.3f m, arc %.0f cm)", TAG, owner_name(g_owner), owner_name(owner), g_ease_sec,
             dist(g_final_p, rel), g_arc_m * 100.0f);
        g_owner = owner;
    }
    const float k = 1.0f - ease((now_s() - g_t0) / g_ease_sec);
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
        // a pair's spot has nobody else setting the hand's target: drawn here every frame, riding the gun
        if (owner == PAIR) player::set_pose(target_of(ik), rp + rotate(rq, g_final_p), qnorm(qmul(rq, g_final_q)));
        return;
    }
    Vec3 lift{0, 0, 0};
    if (g_arc_m > 0.0f) {   // up along the gun's own up (the zone sliders' "up"), in the gun hand's frame; highest mid-way
        Quat gq;
        if (zones::gun_rot(gq)) lift = rotate(qinv(qnorm(rq)), rotate(qnorm(gq), Vec3{0, 1, 0})) * (g_arc_m * 4.0f * k * (1.0f - k));
    }
    g_final_q = qnorm(qmul(slerp_from_identity(g_off_q, k), qrel));
    {   // the palm on a straight line from where it was to where it goes; the wrist placed behind it at this frame's turn
        Vec3 t{};
        if (!rack::palm_offset(t)) t = Vec3{0, 0, 0};
        g_final_p = (rel + rotate(qrel, t)) + g_off_palm * k + lift - rotate(g_final_q, t);
    }
    player::set_pose(target_of(ik), rp + rotate(rq, g_final_p), qnorm(qmul(rq, g_final_q)));
}

} // namespace vn::smooth
