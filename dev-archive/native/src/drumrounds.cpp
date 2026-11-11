// drumrounds.cpp -- see drumrounds.h
#include "drumrounds.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "settings.h"
#include "timings.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <map>
#include <string>
#include <vector>

namespace vn::drumrounds {

using namespace joints;
using namespace vn::settings;

namespace {
struct Chamber {
    MO* j = nullptr;
    Vec3 p{}, s{1, 1, 1};
    Quat q{0, 0, 0, 1};
    bool rest = false;          // its rest numbers were read
    bool used = false;          // we draw it this frame (carried or falling)
    int forced_part = -1;       // the mesh part we switched on for it, -1 none
    bool hidden = false;        // 2026-11-06: its case came out: drawn as an empty chamber (size 0) until a round goes in
    bool part_was = false;      // that part's state before we switched it on
};
// 2026-11-06 (Tefa: "the old shell does not come out at the end of the drum turn automatically and the bullet doesn't travel into
// the chamber visibly"): two moves drawn with a chamber's round joint, both measured against the cover as the gun is NOW (so
// they ride along with the gun in the hand):
//   EJECT   waits for the drum's turn to end, slides out of the chamber backwards through the cover, then drops and tumbles
//   INSERT  from where the right hand held it to just behind the cover, lined up with the barrel, then pushed in, then home
struct Move {
    bool insert = false;
    int i = -1;
    float t0 = 0.0f;            // the move's start (an eject's lies in the future while the drum still turns)
    Vec3 p0{};                  // INSERT: the hand's place at RT; EJECT: where the fall starts (set when the slide ends)
    Quat q0{0, 0, 0, 1};
    bool falling = false;
    float fall_t0 = 0.0f;
    Vec3 v0{};
};

MO* g_wtf = nullptr;
MO* g_mesh = nullptr;
std::vector<Chamber> g_ch;
std::string g_set;              // "Five" / "Seven"
int g_parts_n = 0;
std::vector<int> g_guess;       // the gun's rounds parts (switchVanishEmptyPartsDisp), when one per chamber
std::map<int, int> g_learned;   // chamber -> the part the game switched on when that chamber filled (live)
std::string g_pattern;
int g_last_loaded = -99;
int g_carry = -1;               // the chamber whose round is in the right hand
// 2026-11-11 (Tefa: "as many ammo in the palm of hand, as is either needed to fill the drum or amount in the pouch"): the REST of the
// grab lies in the right palm, drawn with the round joints of chambers that show nothing now (emptied by us, or not loaded). The
// one that goes in next stays between the thumb and index tips (g_carry); each round that goes in takes one out of the palm.
std::vector<int> g_palm;
float g_palm_off[3] = {DRUM_PALM_OFF_CM[0], DRUM_PALM_OFF_CM[1], DRUM_PALM_OFF_CM[2]};   // lid_swing.json "palm_off": along the fingers, across, out of the palm (cm)
float g_palm_step = DRUM_PALM_STEP_CM;                                                   // lid_swing.json "palm_step": one round to the next (cm)
int g_palm_told = -1;
std::vector<Move> g_falls;   // the moves under way (ejects and inserts)
Vec3 g_carry_p{};               // where the carried round was last drawn (an insert starts there)
Quat g_carry_q{0, 0, 0, 1};
int g_lines = 0;
float g_ypr[3] = {DRUM_ROUND_HAND_YPR[0], DRUM_ROUND_HAND_YPR[1], DRUM_ROUND_HAND_YPR[2]};

Quat ypr(float yaw, float pitch, float roll) {   // reload_pose.cpp's convention: about Z, then Y, then X (degrees)
    const float d = 3.14159265f / 360.0f;
    const Quat qz{0, 0, std::sin(yaw * d), std::cos(yaw * d)};
    const Quat qy{0, std::sin(pitch * d), 0, std::cos(pitch * d)};
    const Quat qx{std::sin(roll * d), 0, 0, std::cos(roll * d)};
    return qnorm(qmul(qmul(qz, qy), qx));
}
Quat axis_turn(const Vec3& ax, float deg) { const float h = deg * 3.14159265f / 360.0f, s = std::sin(h); return qnorm({ax.x * s, ax.y * s, ax.z * s, std::cos(h)}); }

bool part_on(int p) { return g_mesh != nullptr && p >= 0 && call_direct<bool>(g_mesh, "getPartsEnable", false, (uint64_t)p); }
void set_part(int p, bool on) {
    static API::Method* m = nullptr;
    static MO* m_for = nullptr;
    if (g_mesh == nullptr || p < 0) return;
    if (m_for != g_mesh) { m = player::overload(g_mesh, "setPartsEnable", 2); m_for = g_mesh; }
    if (m != nullptr) m->call<void>(API::get()->get_vm_context(), (void*)g_mesh, (uint64_t)p, on);
}
std::string pattern() {
    std::string out;
    for (int i = 0; i < g_parts_n && i < 64; ++i) out += part_on(i) ? '1' : '0';
    return out;
}
std::string scales() {
    std::string out;
    char b[24];
    for (auto& c : g_ch) { Vec3 s{}; std::snprintf(b, sizeof(b), "%s%.2f", out.empty() ? "" : " ", c.j && get_v3(JOINT, c.j, "get_LocalScale", s) ? s.x : -1.0f); out += b; }
    return out;
}
int part_for(int i) {
    if (auto it = g_learned.find(i); it != g_learned.end()) return it->second;
    return i >= 0 && i < (int)g_guess.size() ? g_guess[i] : -1;
}

void home(Chamber& c) {
    if (c.j == nullptr || !c.rest) return;
    set_any(JOINT, c.j, "set_LocalPosition", &c.p);
    set_any(JOINT, c.j, "set_LocalRotation", &c.q);
    set_any(JOINT, c.j, "set_LocalScale", &c.s);
}
void let_go(int i, bool keep_part) {   // our hold on chamber i ends; keep_part: the game now draws it itself (the round went in)
    if (i < 0 || i >= (int)g_ch.size()) return;
    Chamber& c = g_ch[i];
    home(c);
    c.hidden = false;
    if (c.forced_part >= 0 && !keep_part) set_part(c.forced_part, c.part_was);
    c.forced_part = -1;
    c.used = false;
}
void show(int i) {   // draw chamber i's round even if the game has it hidden
    Chamber& c = g_ch[i];
    if (c.forced_part < 0) {
        const int p = part_for(i);
        if (p >= 0) { c.part_was = part_on(p); c.forced_part = p; }
    }
    if (c.forced_part >= 0) set_part(c.forced_part, true);
}
void draw_at(int i, const Vec3& p, const Quat& q, float size) {
    Chamber& c = g_ch[i];
    const Vec3 base = c.s.x < 0.01f ? Vec3{1, 1, 1} : c.s;   // a joint the game scaled to nothing is drawn at full size
    const Vec3 sc = base * size;
    set_any(JOINT, c.j, "set_Position", &p);
    set_any(JOINT, c.j, "set_Rotation", &q);
    set_any(JOINT, c.j, "set_LocalScale", &sc);
    show(i);
    c.used = true;
}

bool setup() {
    const auto& s = player::now();
    if (s.weapon_tf == g_wtf && (!g_ch.empty() || g_wtf == nullptr)) return !g_ch.empty();
    // a new gun: the old gun's joints are not touched again (its object may be gone), our state is simply dropped
    g_ch.clear(); g_guess.clear(); g_learned.clear(); g_falls.clear(); g_palm.clear();
    g_wtf = s.weapon_tf;
    g_mesh = nullptr; g_parts_n = 0; g_last_loaded = -99; g_carry = -1; g_lines = 0;
    if (g_wtf == nullptr) return false;
    const int cap = player::capacity();
    for (const char* set : {cap > 5 ? "Seven" : "Five", cap > 5 ? "Five" : "Seven"}) {
        const int n = std::string(set) == "Seven" ? 7 : 5;
        std::vector<Chamber> found(n);
        bool all = true;
        for (int i = 0; i < n; ++i) {
            wchar_t name[32];
            std::swprintf(name, 32, L"%hs_Bullet%02d", set, i);
            found[i].j = joint_by_name(g_wtf, name);
            if (found[i].j == nullptr) { all = false; break; }
            found[i].rest = get_v3(JOINT, found[i].j, "get_LocalPosition", found[i].p) && get_q(JOINT, found[i].j, "get_LocalRotation", found[i].q) &&
                            get_v3(JOINT, found[i].j, "get_LocalScale", found[i].s);
        }
        if (all) {
            for (auto& c : found) if (c.rest && c.s.x < 0.01f) { c.hidden = true; c.s = Vec3{1, 1, 1}; }   // emptied earlier by us
            g_ch = std::move(found); g_set = set; break;
        }
    }
    g_mesh = component(call_ptr(g_wtf, "get_GameObject"), "via.render.Mesh");
    if (g_mesh != nullptr) g_parts_n = (int)call_direct<uint64_t>(g_mesh, "getPartsEnableCount", 0ull);
    if (MO* gun = s.gun; is_managed(gun)) {
        const bool* on = field_ptr<bool>(gun, "IsEnableVanishEmptyPartsDisp");
        std::vector<int> v;
        if (MO* list = field_obj(gun, "switchVanishEmptyPartsDisp")) {
            const int n = call_direct<int>(list, "get_Count", 0);
            for (int i = 0; i < n && i < 64; ++i) v.push_back((int)call_direct<uint32_t>(list, "get_Item", 0u, (int32_t)i));
        }
        std::string vs;
        for (int p : v) vs += (vs.empty() ? "" : " ") + std::to_string(p);
        if (on != nullptr && *on && v.size() == g_ch.size()) g_guess = v;
        LOGI("%s drumrounds: the gun's rounds parts [%s] (%s)%s", TAG, vs.c_str(), on ? (*on ? "on" : "off") : "?",
             g_guess.empty() ? ": not one per chamber, no first guess" : ": one per chamber, used as the first guess");
    }
    g_pattern = pattern();
    LOGI("%s drumrounds: %s_Bullet joints %s (%d), mesh %s with %d parts, drawn now %s, loaded %d, joint sizes %s", TAG, g_set.c_str(),
         g_ch.empty() ? "NOT FOUND: no round in the hand, no falling case" : "found", (int)g_ch.size(), g_mesh ? "found" : "NOT FOUND",
         g_parts_n, g_pattern.c_str(), player::loaded(), scales().c_str());
    return !g_ch.empty();
}

void learn() {   // how the game shows a filled chamber: the part that comes on when the count goes up by one
    const int ld = player::loaded();
    if (ld == g_last_loaded) return;
    const std::string now = pattern();
    if (g_last_loaded >= 0 && ld == g_last_loaded + 1 && now.size() == g_pattern.size()) {
        int on = -1, n = 0;
        for (size_t i = 0; i < now.size(); ++i) if (now[i] == '1' && g_pattern[i] == '0') { on = (int)i; ++n; }
        if (n == 1 && !g_learned.count(g_last_loaded)) {
            g_learned[g_last_loaded] = on;
            LOGI("%s drumrounds: chamber %d is part %d (it came on when the count went %d -> %d)", TAG, g_last_loaded, on, g_last_loaded, ld);
        }
    }
    if (g_lines < 40) {
        ++g_lines;
        LOGI("%s drumrounds: loaded %d -> %d: parts %s -> %s, joint sizes %s", TAG, g_last_loaded, ld, g_pattern.c_str(), now.c_str(), scales().c_str());
    }
    g_pattern = now;
    g_last_loaded = ld;
}

bool carry_pose(Vec3& p, Quat& q) {   // between the right thumb and index tips, turned as the index finger's base
    MO* tf = player::now().tf;
    MO* th = joint_by_name(tf, L"R_Thumb3");
    MO* ix = joint_by_name(tf, L"R_IndexF3");
    MO* ib = joint_by_name(tf, L"R_IndexF1");
    Vec3 a{}, b{};
    if (th == nullptr || ix == nullptr || ib == nullptr || !get_v3(JOINT, th, "get_Position", a) || !get_v3(JOINT, ix, "get_Position", b) ||
        !get_q(JOINT, ib, "get_Rotation", q)) return false;
    q = qnorm(q);
    p = lerp(a, b, 0.5f) + rotate(q, DRUM_ROUND_HAND_OFF);
    // the menu's "round in the hand" sliders, as for the other guns: move (cm, the finger's axes), turn (deg), size (%)
    const auto sv = [](int i) { const float v = bridge::view((bridge::Slot)(bridge::S_SHELL_HOLD + i)); return bridge::has(v) ? v : 0.0f; };
    p = p + rotate(q, Vec3{sv(0), sv(1), sv(2)} * 0.01f);
    q = qnorm(qmul(qmul(q, ypr(g_ypr[0], g_ypr[1], g_ypr[2])), ypr(sv(3), sv(4), sv(5))));
    return true;
}
float carry_size() { const float pct = bridge::has(bridge::view((bridge::Slot)(bridge::S_SHELL_HOLD + 6))) ? bridge::view((bridge::Slot)(bridge::S_SHELL_HOLD + 6)) : 0.0f; return (pct >= 10.0f && pct <= 400.0f) ? pct / 100.0f : 1.0f; }

Quat nlerp(Quat a, Quat b, float u) {
    if (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w < 0.0f) b = {-b.x, -b.y, -b.z, -b.w};
    return qnorm({a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, a.z + (b.z - a.z) * u, a.w + (b.w - a.w) * u});
}
bool busy(int i);
bool moving(int i);
// the cover as the gun is now: its place, the barrel's forward, and a round's turn lined up with the barrel (a resting chamber's)
int g_hole = -1;   // the chamber at the cover, from the last cover_now()
int g_hole_step = DRUM_HOLE_STEP;
bool cover_now(Vec3& lid, Vec3& fwd, Quat& rq) {
    MO* lj = joint_by_name(g_wtf, L"Lid");
    MO* cj = joint_by_name(g_wtf, L"Cylinder");
    MO* mj = joint_by_name(g_wtf, L"vfx_muzzle");
    Vec3 drum{}, muz{};
    if (lj == nullptr || cj == nullptr || mj == nullptr || !get_v3(JOINT, lj, "get_Position", lid) || !get_v3(JOINT, cj, "get_Position", drum) ||
        !get_v3(JOINT, mj, "get_Position", muz)) return false;
    fwd = muz - drum;
    const float n = std::sqrt(fwd.x * fwd.x + fwd.y * fwd.y + fwd.z * fwd.z);
    if (n < 1e-4f) return false;
    fwd = fwd * (1.0f / n);
    // 2026-11-06 (Tefa: "spent casings coming out of the wrong hole, they have to come out of the previous one, the same one they
    // go in from"): the cover joint is the lid's hinge, not the hole. The hole is the chamber nearest the cover: the drum's own
    // place and turn times each chamber's resting local place; both the case and the round use it
    Quat cq{};
    if (get_q(JOINT, cj, "get_Rotation", cq)) {
        cq = qnorm(cq);
        float best = 1e9f;
        Vec3 hole = lid;
        g_hole = -1;
        for (int k = 0; k < (int)g_ch.size(); ++k) {
            const auto& c = g_ch[k];
            if (!c.rest) continue;
            const Vec3 w = drum + rotate(cq, c.p);
            const float d = dist(w, lid);
            if (d < best) { best = d; hole = w; g_hole = k; }
        }
        // 2026-11-07 (Tefa: "rounds go into the one below the chamber guard, so has to be the previous one"): the chamber nearest the
        // lid's hinge is one below the hole: the hole is g_hole_step chambers on (lid_swing.json "hole_step", default -1)
        if (g_hole >= 0 && !g_ch.empty()) {
            const int n = (int)g_ch.size();
            g_hole = ((g_hole + g_hole_step) % n + n) % n;
            if (g_ch[g_hole].rest) hole = drum + rotate(cq, g_ch[g_hole].p);
        }
        lid = hole;
    }
    rq = Quat{0, 0, 0, 1};
    for (int k = 0; k < (int)g_ch.size(); ++k)
        if (!busy(k) && get_q(JOINT, g_ch[k].j, "get_Rotation", rq)) { rq = qnorm(rq); return true; }
    // 2026-11-11: a full hand has every round joint out of the drum: the turn a chamber would have at rest, from the drum's own
    Quat dq{};
    for (int k = 0; k < (int)g_ch.size(); ++k)
        if (g_ch[k].rest && get_q(JOINT, cj, "get_Rotation", dq)) { rq = qnorm(qmul(qnorm(dq), g_ch[k].q)); break; }
    return true;
}
bool moving(int i) {   // at the fingertips, or on its way in / out
    if (i == g_carry) return true;
    for (const auto& f : g_falls) if (f.i == i) return true;
    return false;
}
bool in_palm(int i) { return std::find(g_palm.begin(), g_palm.end(), i) != g_palm.end(); }
bool busy(int i) { return moving(i) || in_palm(i); }
void palm_release(int i) {   // out of the palm, back as its chamber was: an emptied chamber stays empty
    const bool was_hidden = g_ch[i].hidden;
    let_go(i, false);
    if (was_hidden) { const Vec3 zero{0, 0, 0}; g_ch[i].hidden = true; set_any(JOINT, g_ch[i].j, "set_LocalScale", &zero); }
}
Vec3 cross(Vec3 a, Vec3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
float dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
bool unit(Vec3& v) { const float n = std::sqrt(dot(v, v)); if (n < 1e-5f) return false; v = v * (1.0f / n); return true; }
Quat arc(Vec3 from, Vec3 to) {   // the shortest turn that takes unit `from` onto unit `to`
    const float d = dot(from, to);
    if (d < -0.9999f) { Vec3 ax = cross(Vec3{1, 0, 0}, from); if (!unit(ax)) { ax = cross(Vec3{0, 1, 0}, from); unit(ax); } return {ax.x, ax.y, ax.z, 0.0f}; }
    const Vec3 c = cross(from, to);
    return qnorm({c.x, c.y, c.z, 1.0f + d});
}
// the right palm, from the hand's own joints (no axis of the hand joint is assumed): `along` the fingers, `side` from the index
// knuckle to the little finger's, `out` of the palm; base = the middle of the palm
bool palm_frame(Vec3& base, Vec3& along, Vec3& side, Vec3& out) {
    MO* tf = player::now().tf;
    MO* hj = joint_by_name(tf, L"R_Hand");
    MO* ij = joint_by_name(tf, L"R_IndexF1");
    MO* pj = joint_by_name(tf, L"R_PinkyF1");
    Vec3 h{}, i{}, p{};
    if (hj == nullptr || ij == nullptr || pj == nullptr || !get_v3(JOINT, hj, "get_Position", h) || !get_v3(JOINT, ij, "get_Position", i) ||
        !get_v3(JOINT, pj, "get_Position", p)) return false;
    const Vec3 mid = lerp(i, p, 0.5f);
    along = mid - h;
    if (!unit(along)) return false;
    side = (p - i) - along * dot(p - i, along);
    if (!unit(side)) return false;
    out = cross(i - h, p - h);   // right hand, right-handed axes: out of the palm [inferred-static]; "palm_off" z negative turns it over
    if (!unit(out)) return false;
    base = lerp(h, mid, DRUM_PALM_ALONG);
    return true;
}
} // namespace

void point(bool carrying, int rounds) {
    if (!setup()) return;
    learn();
    // the round in the right hand: the chamber that fills next
    const int ld = player::loaded();
    bool inserting = false;
    for (const auto& m : g_falls) inserting = inserting || m.insert;
    // 2026-11-06: the round in the hand is the one that goes into the EMPTIED chamber at the cover (its case came out), so after
    // it goes in, that very chamber shows it; kept for the whole carry
    int want = -1;
    if (carrying && !inserting) {
        if (g_carry >= 0) want = g_carry;
        else {
            Vec3 l0{}, f0{}; Quat r0{};
            cover_now(l0, f0, r0);
            // (2026-11-11: a round lying in the palm may be the one: it moves up to the fingertips)
            if (g_hole >= 0 && g_ch[g_hole].hidden && !moving(g_hole)) want = g_hole;
            for (int k = 0; want < 0 && k < (int)g_ch.size(); ++k) if (g_ch[k].hidden && !moving(k)) want = k;
            if (want < 0 && ld >= 0 && ld < (int)g_ch.size() && !moving(ld)) want = ld;
        }
    }   // (b073 tested busy(ld) alone, which counts the carried one: it flickered)
    if (want != g_carry) {
        if (g_carry >= 0) let_go(g_carry, false);
        g_carry = want;
        if (g_carry >= 0) g_palm.erase(std::remove(g_palm.begin(), g_palm.end(), g_carry), g_palm.end());   // out of the palm, still drawn by us
        if (g_carry >= 0) LOGI("%s drumrounds: chamber %d's round drawn in the right hand (part %d%s)", TAG, g_carry, part_for(g_carry),
                               g_learned.count(g_carry) ? ", learned" : part_for(g_carry) >= 0 ? ", first guess" : ": NOT KNOWN, the joint's size only");
    }
    if (g_carry >= 0) {
        Vec3 p; Quat q;
        if (carry_pose(p, q)) { draw_at(g_carry, p, q, carry_size()); g_carry_p = p; g_carry_q = q; }
    }
    // 2026-11-11: the rest of the grab in the palm: `rounds` are in the hand, one of them at the fingertips (none while one travels
    // into the cover: then they all wait in the palm, and the next moves up when it has gone in)
    {
        const int n = (int)g_ch.size();
        const int palm_want = carrying ? std::max(0, rounds - (g_carry >= 0 ? 1 : 0)) : 0;
        while ((int)g_palm.size() > palm_want) { palm_release(g_palm.back()); g_palm.pop_back(); }
        for (int k = n - 1; (int)g_palm.size() < palm_want && k >= 0; --k)
            if (!busy(k) && (g_ch[k].hidden || k >= ld)) g_palm.push_back(k);
        const int shown = (int)g_palm.size() + (g_carry >= 0 ? 1 : 0);
        if (carrying && shown != g_palm_told) {
            g_palm_told = shown;
            LOGI("%s drumrounds: %d round(s) in the right hand: %d drawn (%d at the fingertips, %d in the palm)%s", TAG, rounds, shown, g_carry >= 0 ? 1 : 0,
                 (int)g_palm.size(), (int)g_palm.size() < palm_want ? ": NOT ENOUGH free round joints for the rest" : "");
        }
        if (!carrying) g_palm_told = -1;
        Vec3 base{}, along{}, side{}, out{};
        if (!g_palm.empty() && palm_frame(base, along, side, out)) {
            // a round's long axis is the barrel's line while it rests in the drum: turned onto the fingers' line
            Vec3 l0{}, f0{}; Quat r0{0, 0, 0, 1};
            Quat q = g_carry_q;
            if (cover_now(l0, f0, r0)) q = qnorm(qmul(arc(f0, along), r0));
            const float size = carry_size();
            const int m = (int)g_palm.size();
            for (int a = 0; a < m; ++a) {
                const float across = (a - (m - 1) * 0.5f) * g_palm_step + g_palm_off[1];
                const Vec3 p = base + along * (g_palm_off[0] * 0.01f) + side * (across * 0.01f) + out * (g_palm_off[2] * 0.01f);
                draw_at(g_palm[a], p, q, size);
            }
        }
    }
    // 2026-11-07 (Tefa: "they get filled again before i actually put the bullet in"): the game's animation writes the drum's joints every
    // frame, so an emptied chamber is drawn empty at every point, not once
    {
        const Vec3 zero{0, 0, 0};
        for (int k = 0; k < (int)g_ch.size(); ++k) if (g_ch[k].hidden && !busy(k)) set_any(JOINT, g_ch[k].j, "set_LocalScale", &zero);
    }
    // the moves: ejects and inserts
    const float now = now_s();
    Vec3 lid{}, fwd{};
    Quat rq{};
    const bool cover = cover_now(lid, fwd, rq);
    for (size_t k = 0; k < g_falls.size();) {
        Move& m = g_falls[k];
        const float t = now - m.t0;
        if (t < 0.0f) { ++k; continue; }   // an eject waiting for the drum's turn to end
        if (m.insert) {
            const float a = timings::v(timings::INSERT_REACH_S), b = timings::v(timings::INSERT_PUSH_S);
            if (t >= a + b || !cover) { let_go(m.i, true); LOGI("%s drumrounds: chamber %d's round pushed in through the cover", TAG, m.i); g_falls.erase(g_falls.begin() + k); continue; }
            const Vec3 entry = lid - fwd * DRUM_ENTRY_BACK_M, inside = lid + fwd * DRUM_PUSH_IN_M;
            Vec3 p; Quat q;
            if (t < a) { const float u = ease(t / a); p = lerp(m.p0, entry, u); q = nlerp(m.q0, rq, u); }
            else { p = lerp(entry, inside, ease((t - a) / b)); q = rq; }
            draw_at(m.i, p, q, 1.0f);
            ++k;
            continue;
        }
        if (!m.falling) {   // the case slides out of its chamber, back through the cover
            const float u = timings::v(timings::CASE_SLIDE_S) > 0.0f ? t / timings::v(timings::CASE_SLIDE_S) : 1.0f;
            if (!cover) { let_go(m.i, false); g_falls.erase(g_falls.begin() + k); continue; }
            const Vec3 p = lerp(lid + fwd * DRUM_PUSH_IN_M, lid - fwd * DRUM_CASE_OUT_M, ease(std::fmin(1.0f, u)));
            draw_at(m.i, p, rq, 1.0f);
            if (u >= 1.0f) { m.falling = true; m.fall_t0 = now; m.p0 = p; m.q0 = rq; m.v0 = fwd * -DRUM_CASE_OUT_MS; }
            ++k;
            continue;
        }
        const float tf = now - m.fall_t0;
        if (tf >= timings::v(timings::CASE_FALL_S)) {   // gone: its chamber is drawn empty until a round goes in
            const int ci = m.i;
            let_go(ci, false);
            const Vec3 zero{0, 0, 0};
            set_any(JOINT, g_ch[ci].j, "set_LocalScale", &zero);
            g_ch[ci].hidden = true;
            g_falls.erase(g_falls.begin() + k);
            continue;
        }
        const Vec3 p = m.p0 + m.v0 * tf + Vec3{0.0f, -4.9f * tf * tf, 0.0f};
        const Quat q = qnorm(qmul(m.q0, axis_turn(Vec3{1, 0, 0}, DRUM_CASE_SPIN_DEG_S * tf)));
        draw_at(m.i, p, q, 1.0f);
        ++k;
    }
}

void inserted() {
    if (g_carry < 0) return;
    Move m;   // it travels from the hand into the cover, then home in its chamber (the game's count draws it from there)
    m.insert = true;
    m.i = g_carry;
    m.t0 = now_s();
    m.p0 = g_carry_p;
    m.q0 = g_carry_q;
    g_falls.push_back(m);
    g_carry = -1;
}

void eject(float delay) {
    if (!setup()) return;
    const auto& s = player::now();
    // the game's own case throw, where the gun has a place to throw it from
    if (DRUM_TRY_GAME_THROW && is_managed(s.gun)) {
        MO* cj = call_ptr(s.gun, "get_cartridgeJoint");
        if (cj != nullptr) {
            call_direct<void*>(s.gun, "ejectCartridge", nullptr);
            LOGI("%s drumrounds: the game's own case throw asked (cartridgeJoint %s)", TAG, read_string(call_ptr(cj, "get_Name")).c_str());
        } else {
            static bool told = false;
            if (!told) { told = true; LOGI("%s drumrounds: the gun has no cartridgeJoint: the game's own case throw is not set up for it; our falling case only", TAG); }
        }
    }
    if (!DRUM_OWN_FALL || g_ch.empty()) return;
    // 2026-11-06: the chamber at the cover gives up its case (a not-yet-emptied one); else any that is free, from the last one back
    int i = -1;
    {
        Vec3 l0{}, f0{}; Quat r0{};
        cover_now(l0, f0, r0);
        if (g_hole >= 0 && !moving(g_hole) && !g_ch[g_hole].hidden) i = g_hole;   // (2026-11-11: also when it lies in the palm, below)
    }
    for (int k = (int)g_ch.size() - 1; i < 0 && k >= 0; --k) if (!busy(k) && !g_ch[k].hidden) i = k;
    // 2026-11-11: a full hand uses every round joint: the case borrows one from the palm (one round fewer there while it falls)
    for (int a = (int)g_palm.size() - 1; i < 0 && a >= 0; --a) if (!g_ch[g_palm[a]].hidden) i = g_palm[a];
    if (i < 0) { LOGI("%s drumrounds: no free chamber joint to draw the falling case with", TAG); return; }
    if (in_palm(i)) { g_palm.erase(std::remove(g_palm.begin(), g_palm.end(), i), g_palm.end()); LOGI("%s drumrounds: chamber %d's joint borrowed from the palm for the falling case", TAG, i); }
    Move m;   // waits for the drum's turn to end, then slides out of the cover and drops (drawn in point())
    m.i = i;
    m.t0 = now_s() + delay;
    g_falls.push_back(m);
    LOGI("%s drumrounds: a spent case comes out of the cover after the drum's turn (chamber %d's joint drawn as it)", TAG, i);
}

void tune(float yaw, float pitch, float roll) { g_ypr[0] = yaw; g_ypr[1] = pitch; g_ypr[2] = roll; }
void tune_hole(int step) { g_hole_step = step; }
void tune_palm(float along_cm, float across_cm, float out_cm, float step_cm) { g_palm_off[0] = along_cm; g_palm_off[1] = across_cm; g_palm_off[2] = out_cm; g_palm_step = step_cm; }

void reset(const char* why) {
    if (g_carry < 0 && g_falls.empty() && g_palm.empty()) return;
    if (player::now().weapon_tf == g_wtf) {   // only the gun still in hand is written to (another gun's object may be gone)
        if (g_carry >= 0) let_go(g_carry, false);
        for (const auto& f : g_falls) let_go(f.i, false);
        for (int i : g_palm) palm_release(i);
    }
    g_carry = -1;
    g_falls.clear();
    g_palm.clear();
    g_palm_told = -1;
    LOGI("%s drumrounds: every round joint home (%s)", TAG, why);
}

} // namespace vn::drumrounds
