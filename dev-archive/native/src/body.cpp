// body.cpp -- see body.h
#include "body.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "settings.h"

#include <windows.h>

#include <cmath>
#include <cstdio>
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
float g_log_t = 0.0f;
float g_tf_yaw = 0.0f, g_look_yaw = 0.0f;

float fwd_yaw(Quat q) { return yaw_of(rotate(q, Vec3{0, 0, 1})); }   // the game's forward is +Z (praydog's re8_vr.lua)

float move_toward(float cur, float target, float dt) {
    const float d = wrap_pi(target - cur);
    // RE2's rule: the step grows with the angle (FirstPerson::update_player_body_rotation: angle / 720 * dt * speed), so a
    // large lag closes fast and a small one gently; a floor so it always finishes
    const float rate = std::fmax(BODY_TURN_MIN_DEG_S * DEG, std::fabs(d) * BODY_TURN_GAIN);
    const float step = std::fmin(std::fabs(d), rate * dt);
    return wrap_pi(cur + (d < 0 ? -step : step));
}

MO* joint_at(MO* joints, int i, bool list) {
    return list ? call_ptr(joints, "get_Item", {(void*)(intptr_t)i}) : call_ptr(joints, "GetValue(System.Int32)", {(void*)(intptr_t)i});
}
} // namespace

float applied_yaw() { return g_theta; }

void frame() {
    g_write = false;
    const auto& s = player::now();
    if (!BODY_TURN_ON || s.tf == nullptr || !bridge::live() || !bridge::flag(bridge::S_CAN_USE_HANDS) || bridge::flag(bridge::S_CUTSCENE)) {
        g_mode = "off";
        g_theta = 0.0f;
        g_have_last_pos = false;
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
    g_look_yaw = fwd_yaw(look);
    const float body_now = wrap_pi(g_tf_yaw + g_theta);

    if (bridge::flag(bridge::S_AIMING) || bridge::held(bridge::S_RGRIP)) {
        g_mode = "aim";
        g_target = wrap_pi(g_look_yaw - g_tf_yaw);
    } else if (g_speed > BODY_WALK_MIN_MPS) {
        // back-pedalling (travel more than BODY_BACKPEDAL_DEG from the look) keeps facing the look, as RE2 does
        const bool backwards = std::fabs(wrap_pi(g_vel_yaw - g_look_yaw)) > BODY_BACKPEDAL_DEG * DEG;
        g_mode = backwards ? "back-pedal" : "walk";
        g_target = wrap_pi((backwards ? g_look_yaw : g_vel_yaw) - g_tf_yaw);
    } else {
        // standing: the body stays until the head is further than the slack; then it comes round to the slack's edge
        const float off = wrap_pi(g_look_yaw - body_now);
        const float slack = BODY_HEAD_SLACK_DEG * DEG;
        g_mode = "stand";
        if (std::fabs(off) > slack) g_target = wrap_pi(g_look_yaw - (off > 0 ? slack : -slack) - g_tf_yaw);
        else g_target = g_theta;
    }
    g_theta = move_toward(g_theta, g_target, dt);
    g_pivot = p;
    g_rot = yaw_quat(g_theta);
    g_write = std::fabs(g_theta) > 0.001f;

    if (t - g_log_t > 1.0f) {
        g_log_t = t;
        LOGI("%s body: mode %s, look %.0f, transform %.0f, drawn %+.0f (target %+.0f), speed %.2f m/s, render check: held %d undone %d", TAG,
             g_mode, g_look_yaw / DEG, g_tf_yaw / DEG, g_theta / DEG, g_target / DEG, g_speed, g_held, g_undone);
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
    static bool told = false;
    if (!told) { told = true; LOGI("%s body: %d joints on the player, turned about the feet by the drawn offset", TAG, n); }
    for (int i = 0; i < n && i < BODY_MAX_JOINTS; ++i) {
        auto* j = joint_at(joints, i, list);
        Vec3 jp;
        Quat jq;
        if (j == nullptr || !get_v3(JOINT, j, "get_Position", jp) || !get_q(JOINT, j, "get_Rotation", jq)) continue;
        Vec3 np = g_pivot + rotate(g_rot, jp - g_pivot);
        Quat nq = qnorm(qmul(g_rot, qnorm(jq)));
        set_any(JOINT, j, "set_Position", &np);
        set_any(JOINT, j, "set_Rotation", &nq);
        if (i == 0) { g_wrote_root_yaw = fwd_yaw(nq); g_wrote = true; }
    }
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
}

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
