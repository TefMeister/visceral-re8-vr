// drumrounds.cpp -- see drumrounds.h
#include "drumrounds.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "settings.h"

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
    bool part_was = false;      // that part's state before we switched it on
};
struct Fall { int i = -1; float t0 = 0.0f; Vec3 p0{}, v0{}; Quat q0{0, 0, 0, 1}; };

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
std::vector<Fall> g_falls;
int g_lines = 0;

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
    g_ch.clear(); g_guess.clear(); g_learned.clear(); g_falls.clear();
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
        if (all) { g_ch = std::move(found); g_set = set; break; }
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
    q = qnorm(qmul(qmul(q, ypr(DRUM_ROUND_HAND_YPR[0], DRUM_ROUND_HAND_YPR[1], DRUM_ROUND_HAND_YPR[2])), ypr(sv(3), sv(4), sv(5))));
    return true;
}
float carry_size() { const float pct = bridge::has(bridge::view((bridge::Slot)(bridge::S_SHELL_HOLD + 6))) ? bridge::view((bridge::Slot)(bridge::S_SHELL_HOLD + 6)) : 0.0f; return (pct >= 10.0f && pct <= 400.0f) ? pct / 100.0f : 1.0f; }

bool busy(int i) {
    if (i == g_carry) return true;
    for (const auto& f : g_falls) if (f.i == i) return true;
    return false;
}
} // namespace

void point(bool carrying) {
    if (!setup()) return;
    learn();
    // the round in the right hand: the chamber that fills next
    const int ld = player::loaded();
    const int want = carrying && ld >= 0 && ld < (int)g_ch.size() ? ld : -1;
    if (want != g_carry) {
        if (g_carry >= 0) let_go(g_carry, false);
        g_carry = want;
        if (g_carry >= 0) LOGI("%s drumrounds: chamber %d's round drawn in the right hand (part %d%s)", TAG, g_carry, part_for(g_carry),
                               g_learned.count(g_carry) ? ", learned" : part_for(g_carry) >= 0 ? ", first guess" : ": NOT KNOWN, the joint's size only");
    }
    if (g_carry >= 0) {
        Vec3 p; Quat q;
        if (carry_pose(p, q)) draw_at(g_carry, p, q, carry_size());
    }
    // the falling cases
    const float now = now_s();
    for (size_t k = 0; k < g_falls.size();) {
        Fall& f = g_falls[k];
        const float t = now - f.t0;
        if (t >= DRUM_CASE_FALL_SEC) { let_go(f.i, false); g_falls.erase(g_falls.begin() + k); continue; }
        const Vec3 p = f.p0 + f.v0 * t + Vec3{0.0f, -4.9f * t * t, 0.0f};
        const Quat q = qnorm(qmul(f.q0, axis_turn(Vec3{1, 0, 0}, DRUM_CASE_SPIN_DEG_S * t)));
        draw_at(f.i, p, q, 1.0f);
        ++k;
    }
}

void inserted() {
    if (g_carry < 0) return;
    let_go(g_carry, true);   // home in its chamber; the game's count draws it from here
    LOGI("%s drumrounds: chamber %d's round went home", TAG, g_carry);
    g_carry = -1;
}

void eject() {
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
    // a chamber not carried and not already falling, from the last one back
    int i = -1;
    for (int k = (int)g_ch.size() - 1; k >= 0; --k) if (!busy(k)) { i = k; break; }
    if (i < 0) { LOGI("%s drumrounds: no free chamber joint to draw the falling case with", TAG); return; }
    Fall f;
    f.i = i;
    f.t0 = now_s();
    Vec3 drum{}, lid{};
    MO* lj = joint_by_name(g_wtf, L"Lid");
    MO* cj = joint_by_name(g_wtf, L"Cylinder");
    const bool have_lid = lj != nullptr && get_v3(JOINT, lj, "get_Position", lid);
    const bool have_drum = cj != nullptr && get_v3(JOINT, cj, "get_Position", drum);
    if (!get_v3(JOINT, g_ch[i].j, "get_Position", f.p0)) return;
    if (!get_q(JOINT, g_ch[i].j, "get_Rotation", f.q0)) f.q0 = Quat{0, 0, 0, 1};
    if (have_lid) f.p0 = lid;
    Vec3 out = have_lid && have_drum ? lid - drum : Vec3{0, 0, 0};
    const float len = std::sqrt(out.x * out.x + out.y * out.y + out.z * out.z);
    f.v0 = len > 1e-4f ? out * (DRUM_CASE_OUT_MS / len) : Vec3{0, 0, 0};
    g_falls.push_back(f);
    LOGI("%s drumrounds: a spent case falls out of the %s (chamber %d's joint drawn as it)", TAG, have_lid ? "cover" : "drum", i);
}

void reset(const char* why) {
    if (g_carry < 0 && g_falls.empty()) return;
    if (player::now().weapon_tf == g_wtf) {   // only the gun still in hand is written to (another gun's object may be gone)
        if (g_carry >= 0) let_go(g_carry, false);
        for (const auto& f : g_falls) let_go(f.i, false);
    }
    g_carry = -1;
    g_falls.clear();
    LOGI("%s drumrounds: every round joint home (%s)", TAG, why);
}

} // namespace vn::drumrounds
