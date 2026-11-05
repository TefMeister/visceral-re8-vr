// reload_pose.cpp -- see reload.h. Moved out of reload.cpp unchanged on 2026-10-24 (the 800-line rule): where the
// magazine and the shell are drawn -- the pose maths, the gun's magazine display and mesh part, the joint writes and
// the joint / part logs. The state they read is reload.cpp's (reload_internal.h).
#include "reload_internal.h"
#include "joints.h"
#include "player.h"
#include "settings.h"
#include "bridge.h"

#include <algorithm>
#include <cmath>
#include <string>

namespace vn::reload::detail {
Vec3 g_shell_scale{1, 1, 1};     // 2026-10-31: the shell joint's own scale, read the first time it is carried (put back by shell_home)
bool g_shell_scale_ok = false;

using namespace joints;
using namespace vn::settings;

namespace {
// Magazine_second (see g_joint2 in reload.cpp): where it sat against "Magazine" at the drop
bool g_j2_ok = false, g_j2_same_parent = false;
Vec3 g_j2_rel_l{}, g_j2_rel_w{}, g_j2_rest_scale{1, 1, 1};
Quat g_j2_rot_l{0, 0, 0, 1}, g_j2_rot_w{0, 0, 0, 1};
} // namespace

Vec3 mag_out_pos() { return g_rest_pos - Vec3{0, RELOAD_MAG_DROP_M, 0}; }

Quat quat_from_ypr(float yaw, float pitch, float roll) {   // yaw about Z, then pitch about Y, then roll about X (degrees)
    const float d = 3.14159265f / 360.0f;
    const Quat qz{0, 0, std::sin(yaw * d), std::cos(yaw * d)};
    const Quat qy{0, std::sin(pitch * d), 0, std::cos(pitch * d)};
    const Quat qx{std::sin(roll * d), 0, 0, std::cos(roll * d)};
    return qnorm(qmul(qmul(qz, qy), qx));
}

bool to_weapon_local(Vec3 world, Quat wrot_in, Vec3& lpos, Quat& lrot) {
    Vec3 wp;
    Quat wr;
    if (!get_v3(XFORM, g_wtf, "get_Position", wp) || !get_q(XFORM, g_wtf, "get_Rotation", wr)) return false;
    const Quat inv = qinv(qnorm(wr));
    lpos = rotate(inv, world - wp);
    lrot = qnorm(qmul(inv, wrot_in));
    return true;
}
bool from_weapon_local(Vec3 lpos, Quat lrot, Vec3& world, Quat& wrot) {
    Vec3 wp;
    Quat wr;
    if (!get_v3(XFORM, g_wtf, "get_Position", wp) || !get_q(XFORM, g_wtf, "get_Rotation", wr)) return false;
    world = wp + rotate(qnorm(wr), lpos);
    wrot = qnorm(qmul(qnorm(wr), lrot));
    return true;
}

bool held_pose(Vec3& pos, Quat& rot) {   // the magazine in the left hand: the hand joint plus the hold
    Vec3 hp;
    Quat hr;
    if (!get_v3(JOINT, g_hand, "get_Position", hp) || !get_q(JOINT, g_hand, "get_Rotation", hr)) return false;
    hr = qnorm(hr);
    pos = hp + rotate(hr, Vec3{MAG_HOLD[0], MAG_HOLD[1], MAG_HOLD[2]});
    rot = qnorm(qmul(hr, quat_from_ypr(MAG_HOLD[3], MAG_HOLD[4], MAG_HOLD[5])));
    return true;
}

// the gun's own magazine switch (WeaponGunCore.switchMagazineDisp / resetMagazineDisp, found in the type list):
// the magazine disappears from the gun while it is out, whichever part it is
void mag_part_shown(bool show);
void magazine_shown(bool show) {
    mag_part_shown(show);
    if (show) call_ptr(g_gun, "resetMagazineDisp");
    else if (auto* m = is_managed(g_gun) ? find_method_deep(g_gun->get_type_definition(), "switchMagazineDisp(System.Boolean)") : nullptr)
        m->call<void>(API::get()->get_vm_context(), (void*)g_gun, false);
}

// the magazine as the gun's mesh part (WeaponGunCore.NormalMagazinePartsNo, ...Customized when customizeMagazine):
// hidden after the gun's animation while it is out (switchMagazineDisp alone showed nothing in the headset, 2026-10-18)
int mag_part() {
    if (!is_managed(g_gun)) return -1;
    bool custom = false;
    player::try_bool(g_gun, "get_customizeMagazine", custom);
    const int* p = field_ptr<int>(g_gun, custom ? "NormalMagazinePartsNoCustomized" : "NormalMagazinePartsNo");
    return p != nullptr ? *p : -1;
}
void mag_part_shown(bool show) {
    const int part = mag_part();
    auto* go = call_ptr(g_wtf, "get_GameObject");   // the gun's owner object (player.cpp)
    auto* mesh = component(go, "via.render.Mesh");
    auto* m = player::overload(mesh, "setPartsEnable", 2);
    static MO* told = nullptr;
    if (told != g_gun) {   // once per gun: what the hide can and cannot reach
        told = g_gun;
        LOGI("%s reload: magazine part %d, gun object %s, mesh %s, setPartsEnable %s", TAG, part, go ? read_string(call_ptr(go, "get_Name")).c_str() : "none",
             mesh ? type_name(mesh).c_str() : "NOT FOUND", m ? "found" : "NOT FOUND");
    }
    if (m == nullptr || part < 0) return;
    m->call<void>(API::get()->get_vm_context(), (void*)mesh, (uint64_t)part, show);
}
void hide_mag_part() { mag_part_shown(false); }

// ---- the joint writes (only when the magazine joint was found) -------------------------------------------------------
void write_local(Vec3 p, Quat q) {
    set_any(JOINT, g_joint, "set_LocalPosition", &p);
    set_any(JOINT, g_joint, "set_LocalRotation", &q);
    if (g_joint2 != nullptr && g_j2_ok && g_j2_same_parent) {
        Vec3 p2 = p + rotate(q, g_j2_rel_l);
        Quat q2 = qnorm(qmul(q, g_j2_rot_l));
        set_any(JOINT, g_joint2, "set_LocalPosition", &p2);
        set_any(JOINT, g_joint2, "set_LocalRotation", &q2);
    }
}
void write_world(Vec3 p, Quat q) {
    set_any(JOINT, g_joint, "set_Position", &p);
    set_any(JOINT, g_joint, "set_Rotation", &q);
    if (g_joint2 != nullptr && g_j2_ok) {
        Vec3 p2 = p + rotate(q, g_j2_rel_w);
        Quat q2 = qnorm(qmul(q, g_j2_rot_w));
        set_any(JOINT, g_joint2, "set_Position", &p2);
        set_any(JOINT, g_joint2, "set_Rotation", &q2);
    }
}
void write_scale(Vec3 s) {
    set_any(JOINT, g_joint, "set_LocalScale", &s);
    if (g_joint2 != nullptr && g_j2_ok) {
        Vec3 s2 = s.x < 0.01f ? Vec3{0, 0, 0} : g_j2_rest_scale;
        set_any(JOINT, g_joint2, "set_LocalScale", &s2);
    }
}
std::string parent_name(MO* joint) {
    MO* p = call_ptr(joint, "get_Parent");
    return p != nullptr ? read_string(call_ptr(p, "get_Name")) : std::string("none");
}
// where the second magazine joint sits against the first, taken at the drop while both still sit in the gun
void capture_second() {
    g_j2_ok = false;
    if (g_joint2 == nullptr) return;
    Vec3 p1l, p2l, p1w, p2w, s2;
    Quat q1l, q2l, q1w, q2w;
    if (!get_v3(JOINT, g_joint, "get_LocalPosition", p1l) || !get_q(JOINT, g_joint, "get_LocalRotation", q1l) ||
        !get_v3(JOINT, g_joint2, "get_LocalPosition", p2l) || !get_q(JOINT, g_joint2, "get_LocalRotation", q2l) ||
        !get_v3(JOINT, g_joint, "get_Position", p1w) || !get_q(JOINT, g_joint, "get_Rotation", q1w) ||
        !get_v3(JOINT, g_joint2, "get_Position", p2w) || !get_q(JOINT, g_joint2, "get_Rotation", q2w)) return;
    if (!get_v3(JOINT, g_joint2, "get_LocalScale", s2) || s2.x < 0.01f) s2 = Vec3{1, 1, 1};
    const std::string a = parent_name(g_joint), b = parent_name(g_joint2);
    g_j2_same_parent = a == b;
    const Quat i1l = qinv(qnorm(q1l)), i1w = qinv(qnorm(q1w));
    g_j2_rel_l = rotate(i1l, p2l - p1l);
    g_j2_rot_l = qnorm(qmul(i1l, qnorm(q2l)));
    g_j2_rel_w = rotate(i1w, p2w - p1w);
    g_j2_rot_w = qnorm(qmul(i1w, qnorm(q2w)));
    g_j2_rest_scale = s2;
    g_j2_ok = true;
    LOGI("%s reload: %s Magazine_second rides along (%.3f m from Magazine); parents: Magazine under %s, Magazine_second under %s%s", TAG,
         g_id.c_str(), dist(p1w, p2w), a.c_str(), b.c_str(), g_j2_same_parent ? "" : " (different: it follows only while falling)");
}
void shell_write(Vec3 p, Quat q) {
    set_any(JOINT, g_shell, "set_LocalPosition", &p);
    set_any(JOINT, g_shell, "set_LocalRotation", &q);
}
// 2026-10-24 (board: "the pouch shell moves a little with the right controller"): the shell's local numbers were taken
// against the gun object, but a joint's local is against its PARENT joint. The M1897's Bullet sits at local
// (0, -0.015, -0.013), which only makes sense under Body (local 0, 0.030, 0.222 from the root, joint log 2026-10-24), so
// the shell was most likely off by Body's place and swung with the gun's turn [inferred-static]. Now it is written in
// the world (as the falling magazine is), which needs no parent; the parent is logged once per gun to settle it.
void pose_shell() {   // the gun's shell joint rides in the left hand while a round is carried
    if (g_shell == nullptr || !g_round_in_hand) return;
    Vec3 wp, lp;
    Quat wr, lr;
    if (!held_pose(wp, wr)) return;
    // 2026-10-31 (Tefa: "the shell does not stay put, it shifts around with my hand rotation"): the 7 cm was taken straight
    // down in the WORLD every frame, so turning the wrist slid the shell across the palm. b020 measured it once per pickup,
    // which made every round land somewhere else (Tefa, screenshots 22:14: "always ends up a little shifted seemingly
    // randomly"; log: 20 pickups, two groups 11 cm apart). Now ONE fixed spot in the hold's own axes, SHELL_DROP_LOCAL:
    // the mean of the last nine pickups, the ones Tefa tuned the sliders against.
    wp = wp + rotate(qnorm(wr), Vec3{SHELL_DROP_LOCAL[0], SHELL_DROP_LOCAL[1], SHELL_DROP_LOCAL[2]});
    // 2026-10-31: the menu's sliders for the round in the hand (per gun): move along the hold's own axes, turn, size
    const auto sv = [](int i) { const float v = bridge::view((bridge::Slot)(bridge::S_SHELL_HOLD + i)); return bridge::has(v) ? v : 0.0f; };
    wp = wp + rotate(qnorm(wr), Vec3{sv(0), sv(1), sv(2)} * 0.01f);
    wr = qnorm(qmul(qnorm(wr), quat_from_ypr(sv(3), sv(4), sv(5))));
    const float pct = sv(6);
    const float k = (pct >= 10.0f && pct <= 400.0f) ? pct / 100.0f : 1.0f;
    if (!g_shell_scale_ok) {
        Vec3 s0;
        g_shell_scale = (get_v3(JOINT, g_shell, "get_LocalScale", s0) && s0.x > 0.01f) ? s0 : Vec3{1, 1, 1};
        g_shell_scale_ok = true;
    }
    const Vec3 sc = g_shell_scale * k;
    set_any(JOINT, g_shell, "set_LocalScale", &sc);
    static float told_k = -1.0f;
    if (std::fabs(k - told_k) > 0.005f) { told_k = k; LOGI("%s reload: %s round in the hand: size %.0f%% (menu)", TAG, g_id.c_str(), k * 100.0f); }
    static std::string told;
    if (told != g_id) {
        told = g_id;
        MO* parent = call_ptr(g_shell, "get_Parent");
        Vec3 pl{};
        const bool have = parent != nullptr && get_v3(JOINT, parent, "get_LocalPosition", pl);
        LOGI("%s reload: %s shell joint Bullet hangs under %s (its local %.3f %.3f %.3f); placed %s", TAG, g_id.c_str(),
             parent_name(g_shell).c_str(), have ? pl.x : 0.0f, have ? pl.y : 0.0f, have ? pl.z : 0.0f, SHELL_WORLD_WRITE ? "in the world" : "by gun-local numbers");
    }
    if (SHELL_WORLD_WRITE) {
        set_any(JOINT, g_shell, "set_Position", &wp);
        set_any(JOINT, g_shell, "set_Rotation", &wr);
    } else if (to_weapon_local(wp, wr, lp, lr)) {
        shell_write(lp, lr);
    }
}
void shell_home() {
    if (g_shell != nullptr && g_shell_scale_ok) set_any(JOINT, g_shell, "set_LocalScale", &g_shell_scale);   // 2026-10-31: its own size back
    if (g_shell != nullptr && g_shell_have_rest) shell_write(g_shell_rest, g_shell_rest_rot);
}

// the gun's mesh parts and whether each is drawn, once per gun: which one is the loose shell (2026-10-19)
void log_parts() {
    auto* mesh = component(call_ptr(g_wtf, "get_GameObject"), "via.render.Mesh");
    auto* cnt = player::overload(mesh, "getPartsEnableCount", 0);
    auto* get = player::overload(mesh, "getPartsEnable", 1);
    if (cnt == nullptr || get == nullptr) return;
    auto* ctx = API::get()->get_vm_context();
    const uint64_t n = cnt->call<uint64_t>(ctx, (void*)mesh);
    std::string on;
    for (uint64_t i = 0; i < n && i < 64; ++i) on += get->call<bool>(ctx, (void*)mesh, i) ? '1' : '0';
    LOGI("%s mesh parts of %s: %llu, drawn now: %s", TAG, g_id.c_str(), (unsigned long long)n, on.c_str());
}

void pose_joint() {
    if (g_joint == nullptr || g_w == nullptr) return;
    const float t = now_s() - g_t0;
    switch (g_st) {
    case St::SEATED:
        if (g_scale_restore) { write_scale(g_rest_scale); g_scale_restore = false; }
        return;
    case St::SLIDE_OUT:
        write_local(lerp(g_rest_pos, mag_out_pos(), ease(t / RELOAD_SLIDE_SEC)), g_rest_rot);
        return;
    case St::FALL:
    case St::HAND_FALL: {
        const float u = std::fmin(1.0f, t / RELOAD_FALL_SEC);
        write_world(g_fall_from - Vec3{0, RELOAD_FALL_M * u * u, 0}, g_fall_rot);
        return;
    }
    case St::OUT:
        mag_part_shown(false);
        write_scale(Vec3{0, 0, 0});
        write_local(g_rest_pos, g_rest_rot);
        return;
    case St::IN_HAND: {
        mag_part_shown(true);
        Vec3 wp, lp;
        Quat wr, lr;
        if (!held_pose(wp, wr) || !to_weapon_local(wp, wr, lp, lr)) return;
        write_scale(g_rest_scale);
        write_local(lp, lr);
        return;
    }
    case St::INSERT:
        write_scale(g_rest_scale);
        write_local(lerp(mag_out_pos(), g_rest_pos, ease(t / RELOAD_INSERT_SEC)), g_rest_rot);
        return;
    }
}

void log_joints() {
    auto* joints = call_ptr(g_wtf, "get_Joints");
    int n = call_direct<int>(joints, "get_Length", 0);
    const bool list = n <= 0;   // Andyalpa's RE7 scan used get_Count / get_Item (2026-10-18: get_Length gave nothing)
    if (list) n = call_direct<int>(joints, "get_Count", 0);
    LOGI("%s joints of %s: %d (%s), magazine mesh part %d, gun transform %s", TAG, g_id.c_str(), n, joints ? type_name(joints).c_str() : "no list",
         mag_part(), g_wtf ? "found" : "NOT FOUND");
    if (n <= 0) {   // backup: ask for the usual numbered joint names one by one
        for (int k = 0; k <= 20; ++k) {
            wchar_t nm[8];
            swprintf(nm, 8, L"_%02d", k);
            auto* j = joint_by_name(g_wtf, nm);
            Vec3 p{};
            if (j != nullptr && get_v3(JOINT, j, "get_LocalPosition", p)) LOGI("%s joint %s %ls local %.3f %.3f %.3f", TAG, g_id.c_str(), nm, p.x, p.y, p.z);
        }
    }
    for (int i = 0; i < n && i < JOINT_LOG_MAX; ++i) {
        auto* j = list ? call_ptr(joints, "get_Item", {(void*)(intptr_t)i}) : call_ptr(joints, "GetValue(System.Int32)", {(void*)(intptr_t)i});
        Vec3 p{};
        get_v3(JOINT, j, "get_LocalPosition", p);
        LOGI("%s joint %s[%d] %s local %.3f %.3f %.3f", TAG, g_id.c_str(), i, read_string(call_ptr(j, "get_Name")).c_str(), p.x, p.y, p.z);
    }
}

} // namespace vn::reload::detail

// 2026-11-05 (Tefa 2026-10-31: "the mag that goes in full from the pouch when the gun is empty ... the mag in hand changes to the
// empty model when that one last round is fired"): the rounds the OUT magazine holds, for its look (magdisp.cpp). The one
// pulled out keeps what it left with; a fresh one from the pouch is as full as the carried ammo (plus the dropped one's
// rounds, which fill_magazine gives back) allows
namespace vn::reload {
int mag_rounds_out() {
    using namespace detail;
    if (!mag_out()) return -1;
    const bool fresh = (g_st == St::IN_HAND || g_st == St::INSERT) && !g_same_mag;
    if (!fresh) return std::max(0, g_mag_rounds);
    const int cap = player::capacity();
    if (player::unlimited()) return cap > 0 ? cap : 1;
    const int have = std::max(0, player::reserve()) + std::max(0, g_mag_rounds);
    return cap > 0 ? std::min(cap, have) : have;
}
} // namespace vn::reload
