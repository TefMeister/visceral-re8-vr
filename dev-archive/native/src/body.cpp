// body.cpp -- see body.h
#include "body.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "settings.h"

#include <windows.h>

#include <cmath>
#include <cstdio>
#include <cstring>
#include <tuple>
#include <filesystem>
#include <string>
#include <vector>

namespace vn::body {

using namespace joints;
using namespace vn::settings;

namespace {
constexpr float PI = 3.14159265f;
constexpr float DEG = PI / 180.0f;

float g_theta = 0.0f;           // the offset drawn: body yaw = transform yaw + theta
float g_target = 0.0f;          // where theta is heading
const char* g_mode = "off";
bool g_write = false;           // this frame's late write is due
float g_last_t = -1.0f;
Vec3 g_last_pos{};
bool g_have_last_pos = false;
float g_vel_yaw = 0.0f;         // the direction of travel, when moving
float g_speed = 0.0f;
Vec3 g_pivot{};
Quat g_rot{0, 0, 0, 1};
float g_wrote_root_yaw = 0.0f;  // the root joint's yaw after our write
bool g_wrote = false;
int g_held = 0, g_undone = 0;
Vec3 g_root_p{};
Quat g_root_q{0, 0, 0, 1};
MO* g_root = nullptr;   // the root joint and the turn written at the late write (written again before the draw)
MO* g_j[BODY_MAX_JOINTS] = {};   // every joint turned this frame (BODY_ALL_JOINTS)
Vec3 g_p[BODY_MAX_JOINTS] = {};
Quat g_q[BODY_MAX_JOINTS] = {};
bool g_ok[BODY_MAX_JOINTS] = {};
bool g_skip[BODY_MAX_JOINTS] = {};
int g_n = 0, g_names_n = -1, g_skip_n = 0;
bool skip_joint(const std::string& nm) {   // the arm chains (the hands stay on the controllers) and the head
    static const char* words[] = {"Shoulder", "Clavicle", "UpperArm", "Arm", "Elbow", "Forearm", "Wrist", "Hand", "Palm", "Thumb", "Index", "Middle", "Ring", "Pinky", "Head"};
    for (const char* w : words) if (nm.find(w) != std::string::npos) return true;
    return false;
}
float g_log_t = 0.0f;
float g_tf_yaw = 0.0f, g_look_yaw = 0.0f;
bool g_catching = false;        // standing: the body is coming round to the look (until within 2 deg)
float g_body_yaw = 0.0f;        // the body's own facing in the world (2026-10-25)
bool g_body_init = false;
bool g_was_blocked = false;

float fwd_yaw(Quat q) { return yaw_of(rotate(q, Vec3{0, 0, 1})); }   // the game's forward is +Z (praydog's re8_vr.lua)

float move_toward(float cur, float target, float dt, float gain = BODY_TURN_GAIN) {
    const float d = wrap_pi(target - cur);
    // RE2's rule: the step grows with the angle (FirstPerson::update_player_body_rotation: angle / 720 * dt * speed), so a
    // large lag closes fast and a small one gently; a floor so it always finishes
    const float rate = std::fmax(BODY_TURN_MIN_DEG_S * DEG, std::fabs(d) * gain);
    const float step = std::fmin(std::fabs(d), rate * dt);
    return wrap_pi(cur + (d < 0 ? -step : step));
}

MO* joint_at(MO* joints, int i, bool list) {
    return list ? call_ptr(joints, "get_Item", {(void*)(intptr_t)i}) : call_ptr(joints, "GetValue(System.Int32)", {(void*)(intptr_t)i});
}
} // namespace

// ---- THE INVENTORY (2026-10-25): the interaction flag never fired in the inventory, so the game's own calls are hooked:
// app.MenuManager.openInventoryMenu / app.GUIInventory.openInventory (the ones praydog's re8_vr.lua hooks for its 0.25 s
// window) set it, and the matching close calls clear it; a steady isOpenInventoryMenu, when the type has one, is read too
bool g_inv_open = false;
MO* g_menu_mgr = nullptr;
API::Method* g_is_open = nullptr;
bool g_is_open_looked = false;
int inv_pre_open(int, void**, REFrameworkTypeDefinitionHandle*, unsigned long long) { if (!g_inv_open) LOGI("%s body: the inventory opened", TAG); g_inv_open = true; return REFRAMEWORK_HOOK_CALL_ORIGINAL; }
int inv_pre_close(int, void**, REFrameworkTypeDefinitionHandle*, unsigned long long) { if (g_inv_open) LOGI("%s body: the inventory closed", TAG); g_inv_open = false; return REFRAMEWORK_HOOK_CALL_ORIGINAL; }
bool menu_open() {
    if (!g_is_open_looked) {
        g_is_open_looked = true;
        g_menu_mgr = (MO*)API::get()->get_managed_singleton("app.MenuManager");
        g_is_open = g_menu_mgr != nullptr ? find_method_deep(g_menu_mgr->get_type_definition(), "isOpenInventoryMenu") : nullptr;
        LOGI("%s body: app.MenuManager %s, isOpenInventoryMenu %s", TAG, g_menu_mgr ? "found" : "MISSING", g_is_open ? "found (read every frame)" : "not there (the open / close hooks decide)");
    }
    if (g_is_open != nullptr && is_managed(g_menu_mgr)) {
        auto r = g_is_open->invoke(g_menu_mgr, std::vector<void*>{});
        if (!r.exception_thrown) return r.byte != 0 || g_inv_open;
    }
    return g_inv_open;
}
void install() {
    int n = 0;
    for (auto [type, name, open] : {std::tuple{"app.MenuManager", "openInventoryMenu", true}, std::tuple{"app.MenuManager", "closeInventoryMenu", false},
                                   std::tuple{"app.GUIInventory", "openInventory", true}, std::tuple{"app.GUIInventory", "closeInventory", false}}) {
        auto* m = API::get()->tdb()->find_method(type, name);
        if (m == nullptr) { LOGI("%s body: %s.%s not found", TAG, type, name); continue; }
        m->add_hook(open ? inv_pre_open : inv_pre_close, nullptr, false);
        ++n;
    }
    LOGI("%s body: %d inventory open / close call(s) hooked", TAG, n);
}

float applied_yaw() { return g_theta; }

void frame() {
    g_write = false;
    const auto& s = player::now();
    if (!BODY_TURN_ON || !bridge::flag(bridge::S_BODY_TURN) || s.tf == nullptr || !bridge::live() || !bridge::flag(bridge::S_CAN_USE_HANDS) || bridge::flag(bridge::S_CUTSCENE)) {
        g_mode = "off";
        g_theta = 0.0f;
        g_have_last_pos = false;
        g_body_init = false;
        return;
    }
    Vec3 p;
    Quat q;
    if (!player::get_pose(s.tf, p, q)) return;
    const float t = now_s();
    const float dt = g_last_t < 0 ? 0.0f : std::fmin(0.1f, t - g_last_t);
    g_last_t = t;

    // the direction of travel from the transform's own movement
    if (g_have_last_pos && dt > 0.0f) {
        const Vec3 d{p.x - g_last_pos.x, 0.0f, p.z - g_last_pos.z};
        const float len = std::sqrt(d.x * d.x + d.z * d.z);
        g_speed = len / dt;
        if (g_speed > BODY_WALK_MIN_MPS) g_vel_yaw = yaw_of(d);
    }
    g_last_pos = p;
    g_have_last_pos = true;

    Quat look;
    if (!bridge::room_rot_to_world(bridge::hmd_rot(), look)) return;
    g_tf_yaw = fwd_yaw(q);
    // 2026-10-24 first wear: look and transform read 180 apart while looking straight ahead: the headset's rotation carried
    // into the world looks down -Z (the camera's convention), the player transform faces +Z
    g_look_yaw = yaw_of(rotate(look, Vec3{0, 0, -1}));

    // 2026-10-25 00:25 (Tefa: "his body should not turn with head turning when walking, right now his body is like attached
    // to hmd so there is no neck rotation, the whole body is one solid chunk"; the log: standing, the transform itself snaps
    // after the look in steps, 129 -> 123 -> 80 -> 97 -> 79): the lag used to be an offset ON the transform, so every snap
    // of the transform turned the drawn body at once. Now the body has its OWN facing in the world (g_body_yaw), turned
    // toward its target at its own pace whatever the transform does; the drawn offset is that facing minus the transform's.
    if (!g_body_init) { g_body_yaw = g_tf_yaw; g_body_init = true; }
    const bool blocked = bridge::flag(bridge::S_INTERACTION_BLOCKED) || menu_open();
    if (blocked != g_was_blocked) {
        g_was_blocked = blocked;
        LOGI("%s body: %s", TAG, blocked ? "a menu / the inventory is up: the body holds still" : "menu closed: the body turns again");
    }
    if (blocked) {
        // (00:25 / 00:35, Tefa: "ethan's body still goes crazy in the inventory screen"; the log: the body kept writing through
        // the inventory, the interaction flag never fired): nothing is written at all while a menu is up; the body starts
        // again from the transform's facing when it closes
        g_mode = "menu";
        g_theta = 0.0f;
        g_body_yaw = g_tf_yaw;
        g_catching = false;
        g_write = false;
        return;
    }
    // 2026-10-25, Tefa's rule: the body only comes round once the head is further off it than the deadzone of the moment:
    // standing 60 deg, walking 45, running 30; then it turns, slowly, until it faces where the head looks ("straight
    // forward is 0 then"). Aiming: it faces the look. Walking with the head inside the deadzone: the head turns on the neck
    float target = g_body_yaw;
    float gain = BODY_FOLLOW_GAIN, floor_deg_s = BODY_FOLLOW_MIN_DEG_S;
    const float off = wrap_pi(g_look_yaw - g_body_yaw);
    if (bridge::flag(bridge::S_AIMING) || bridge::held(bridge::S_RGRIP)) {
        g_mode = "aim";
        target = g_look_yaw;
        gain = BODY_TURN_GAIN;
        floor_deg_s = BODY_TURN_MIN_DEG_S;
        g_catching = false;
    } else {
        float dead = BODY_STAND_DEADZONE_DEG;
        if (g_speed > BODY_RUN_MIN_MPS) { g_mode = "run"; dead = BODY_RUN_DEADZONE_DEG; }
        else if (g_speed > BODY_WALK_MIN_MPS) { g_mode = "walk"; dead = BODY_WALK_DEADZONE_DEG; }
        else g_mode = "stand";
        if (std::fabs(off) > dead * DEG || g_catching) { target = g_look_yaw; g_catching = std::fabs(off) > 2.0f * DEG; }
    }
    {
        const float d = wrap_pi(target - g_body_yaw);
        const float rate = std::fmax(floor_deg_s * DEG, std::fabs(d) * gain);
        const float step = std::fmin(std::fabs(d), rate * dt);
        g_body_yaw = wrap_pi(g_body_yaw + (d < 0 ? -step : step));
    }
    g_target = wrap_pi(target - g_tf_yaw);
    g_theta = wrap_pi(g_body_yaw - g_tf_yaw);
    const float lim = BODY_MAX_OFFSET_DEG * DEG;   // never further than this from the transform (the arms hang off it)
    if (std::fabs(g_theta) > lim) { g_theta = g_theta > 0 ? lim : -lim; g_body_yaw = wrap_pi(g_tf_yaw + g_theta); }
    g_pivot = p;
    g_rot = yaw_quat(g_theta);
    g_write = std::fabs(g_theta) > 0.001f;

    if (t - g_log_t > 1.0f) {
        g_log_t = t;
        LOGI("%s body: mode %s, look %.0f, transform %.0f, body %.0f (drawn %+.0f, target %+.0f), speed %.2f m/s, render check: held %d undone %d", TAG,
             g_mode, g_look_yaw / DEG, g_tf_yaw / DEG, g_body_yaw / DEG, g_theta / DEG, g_target / DEG, g_speed, g_held, g_undone);
    }
}

void late_point() {
    g_wrote = false;
    if (!g_write) return;
    const auto& s = player::now();
    auto* joints = call_ptr(s.tf, "get_Joints");
    int n = call_direct<int>(joints, "get_Length", 0);
    const bool list = n <= 0;
    if (list) n = call_direct<int>(joints, "get_Count", 0);
    if (n <= 0) return;
    // 2026-10-24 first wear (Tefa's screenshots: Ethan torn into strips): every joint was turned, but a child's world pose
    // already carries its parent's turn, so each joint was turned again down the chain. Only the ROOT joint is turned now;
    // the rest of the skeleton hangs off it and follows.
    // 2026-10-25 01:50 (Tefa, after the write-before-the-draw: "chest and body still the same"): the root alone is never
    // drawn turned. Every joint is now turned (read ALL first, then written: the 2026-10-24 strips came from reading a child
    // after its parent was already turned), except the arm chains (the hands stay on the controllers) and the head
    if (BODY_ALL_JOINTS) {
        if (n > BODY_MAX_JOINTS) n = BODY_MAX_JOINTS;
        if (g_names_n != n) {   // the joint names, once per skeleton: which ones are skipped
            g_names_n = n;
            g_skip_n = 0;
            for (int i = 0; i < n; ++i) {
                auto* ji = joint_at(joints, i, list);
                const std::string nm = ji ? read_string(call_ptr(ji, "get_Name")) : "";
                g_skip[i] = skip_joint(nm);
                if (g_skip[i]) ++g_skip_n;
            }
            LOGI("%s body: %d joints, %d of them left alone (arms, hands, head)", TAG, n, g_skip_n);
        }
        int got = 0;
        for (int i = 0; i < n; ++i) {
            g_j[i] = joint_at(joints, i, list);
            g_ok[i] = g_j[i] != nullptr && !g_skip[i] && get_v3(JOINT, g_j[i], "get_Position", g_p[i]) && get_q(JOINT, g_j[i], "get_Rotation", g_q[i]);
            if (g_ok[i]) ++got;
        }
        // 02:10 (Tefa: "the body is a mess ... body swings into the view"): the turn was about the player transform's position,
        // which is not under Ethan; it is about his own root joint now (its position read before anything is turned)
        const Vec3 piv = g_ok[0] ? Vec3{g_p[0].x, g_pivot.y, g_p[0].z} : g_pivot;
        const float before = g_ok[0] ? fwd_yaw(g_q[0]) : 0.0f;
        for (int i = 0; i < n; ++i) {
            if (!g_ok[i]) continue;
            g_p[i] = piv + rotate(g_rot, g_p[i] - piv);
            g_q[i] = qnorm(qmul(g_rot, qnorm(g_q[i])));
            set_any(JOINT, g_j[i], "set_Position", &g_p[i]);
            set_any(JOINT, g_j[i], "set_Rotation", &g_q[i]);
        }
        g_n = n;
        if (got > 0 && g_ok[0]) {
            g_wrote_root_yaw = fwd_yaw(g_q[0]); g_root = g_j[0]; g_root_p = g_p[0]; g_root_q = g_q[0];
            static float told_t = -10.0f;
            if (now_s() - told_t > 1.0f) {   // the direction check: after = before + drawn, and after should equal body
                told_t = now_s();
                LOGI("%s body: root yaw before %.0f, after %.0f (drawn %+.0f), transform %.0f, body %.0f, look %.0f, pivot %.2f m from the transform", TAG,
                     before / DEG, g_wrote_root_yaw / DEG, g_theta / DEG, g_tf_yaw / DEG, g_body_yaw / DEG, g_look_yaw / DEG, dist(piv, g_pivot));
            }
        }
        g_wrote = got > 0;
        return;
    }
    auto* j = joint_at(joints, 0, list);
    Vec3 jp;
    Quat jq;
    if (j == nullptr || !get_v3(JOINT, j, "get_Position", jp) || !get_q(JOINT, j, "get_Rotation", jq)) return;
    static bool told = false;
    if (!told) { told = true; LOGI("%s body: the root joint %s (of %d) is turned about the feet by the drawn offset", TAG, read_string(call_ptr(j, "get_Name")).c_str(), n); }
    Vec3 np = g_pivot + rotate(g_rot, jp - g_pivot);
    Quat nq = qnorm(qmul(g_rot, qnorm(jq)));
    set_any(JOINT, j, "set_Position", &np);
    set_any(JOINT, j, "set_Rotation", &nq);
    g_wrote_root_yaw = fwd_yaw(nq);
    g_root = j;
    g_root_p = np;
    g_root_q = nq;
    g_wrote = true;
}

// 2026-10-25 01:25 (Tefa, after five builds: "chest turns with my head - no change still"): the LateUpdateBehavior write held
// to PrepareRendering post (the check), but the engine re-poses the skeleton once more before the draw (the shotgun's pump
// joint needed its second write at BeginRendering for the same reason). The turned root is now written again here and at
// BeginRendering pre, from the turn kept at the late write
void write_root_again() {
    if (!g_wrote) return;
    if (BODY_ALL_JOINTS) {
        for (int i = 0; i < g_n; ++i) if (g_ok[i]) { set_any(JOINT, g_j[i], "set_Position", &g_p[i]); set_any(JOINT, g_j[i], "set_Rotation", &g_q[i]); }
        return;
    }
    if (g_root == nullptr) return;
    set_any(JOINT, g_root, "set_Position", &g_root_p);
    set_any(JOINT, g_root, "set_Rotation", &g_root_q);
}
void render_point() {
    if (!g_wrote) return;
    const auto& s = player::now();
    auto* joints = call_ptr(s.tf, "get_Joints");
    int n = call_direct<int>(joints, "get_Length", 0);
    auto* root = joint_at(joints, 0, n <= 0);
    Quat rq;
    if (root == nullptr || !get_q(JOINT, root, "get_Rotation", rq)) return;
    if (std::fabs(wrap_pi(fwd_yaw(rq) - g_wrote_root_yaw)) < 2.0f * DEG) ++g_held; else ++g_undone;
    write_root_again();
}
void begin_render() { write_root_again(); }

// which game types carry the game's own body-direction machinery (its third-person mode): once, into type_probe.txt
void probe_types() {
    auto* tdb = API::get()->tdb();
    const uint32_t n = tdb->get_num_types();
    std::vector<API::TypeDefinition*> hits;
    for (uint32_t i = 0; i < n; ++i) {
        auto* td = tdb->get_type(i);
        if (td == nullptr) continue;
        const std::string tn = td->get_full_name();
        if (tn.rfind("app.", 0) != 0) continue;
        if (tn.find("Player") == std::string::npos && tn.find("Character") == std::string::npos && tn.find("Camera") == std::string::npos) continue;
        for (const char* m : {"calculateBodyDirection", "set_bodyDirectionTarget", "getCameraYaw", "get_isTPSMode", "set_turnAngle"}) {
            if (td->find_method(m) != nullptr) { hits.push_back(td); LOGI("%s body: %s has %s", TAG, tn.c_str(), m); break; }
        }
    }
    if (hits.empty()) { LOGI("%s body: no app.Player/Character/Camera type has the body-direction calls", TAG); return; }
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto path = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "type_probe.txt";
    FILE* f = nullptr;
    if (_wfopen_s(&f, path.c_str(), L"ab") != 0 || f == nullptr) return;
    for (auto* td : hits) {
        std::fprintf(f, "==== %s (body direction, 2026-10-24)\n", td->get_full_name().c_str());
        for (auto* m : td->get_methods()) {
            if (m == nullptr) continue;
            auto* rt = m->get_return_type();
            std::fprintf(f, "  M %s", m->get_name());
            const auto params = m->get_params();
            std::fprintf(f, "(");
            for (size_t k = 0; k < params.size(); ++k) {
                auto* pt = (API::TypeDefinition*)params[k].t;
                std::fprintf(f, "%s%s", k ? ", " : "", pt ? pt->get_full_name().c_str() : "?");
            }
            std::fprintf(f, ") -> %s\n", rt ? rt->get_full_name().c_str() : "?");
        }
        for (auto* fd : td->get_fields()) {
            if (fd == nullptr) continue;
            auto* ft = fd->get_type();
            std::fprintf(f, "  F %s%s : %s\n", fd->is_static() ? "static " : "", fd->get_name(), ft ? ft->get_full_name().c_str() : "?");
        }
    }
    std::fclose(f);
}

} // namespace vn::body
