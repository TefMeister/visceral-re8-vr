// leanrec.cpp -- see leanrec.h
#include "leanrec.h"

#include "base.h"
#include "bridge.h"
#include "jointwriter.h"
#include "ready.h"

#include <algorithm>

namespace vr8::leanrec {

namespace {
constexpr int JOINTS = 3;
const wchar_t* const JOINT_NAMES[JOINTS] = {L"Neck_0", L"Spine_2", L"Hip"};
const char* const JOINT_SAY[JOINTS] = {"neck", "spine2", "hip"};
constexpr float WINDOW_S = 0.5f;
constexpr float WORTH_M = 0.04f;           // a window in which a joint's "behind the eyes" changed less: no line
constexpr int MAX_LINES = 1500;

struct Range { float lo = 1e9f, hi = -1e9f; void add(float v) { lo = std::min(lo, v); hi = std::max(hi, v); } };

unsigned g_generation = 0;
MO* g_joint[JOINTS]{};
bool g_looked = false;
Range g_behind[JOINTS], g_side[JOINTS];
float g_window_at = -1.0f, g_path_m = 0.0f;
Vec3 g_last_at{};
bool g_have_last = false;
int g_lines = 0;

Call& joint_position() { static Call c("via.Joint", "get_Position", 0); return c; }
Call& transform_position() { static Call c("via.Transform", "get_Position", 0); return c; }
Call& transform_rotation() { static Call c("via.Transform", "get_Rotation", 0); return c; }

// the main camera's transform, the way the scripts' sdk.get_primary_camera() finds it
MO* camera_transform() {
    static Call main_view("via.SceneManager", "get_MainView", 0);
    static Call primary_camera("via.SceneView", "get_PrimaryCamera", 0);
    static Call object_transform("via.GameObject", "get_Transform", 0);
    MO* view = main_view.ptr(API::get()->get_native_singleton("via.SceneManager"));
    MO* camera = primary_camera.ptr(view);
    return object_transform.ptr(dyn_ptr(camera, "get_GameObject"));
}
} // namespace

void pose() {
    const auto& player = ready::now();
    if (player.generation != g_generation) {
        g_generation = player.generation;
        g_looked = g_have_last = false;
        g_window_at = -1.0f;
    }
    if (player.transform == nullptr || !bridge::live() || !bridge::flag(bridge::S_ACTIVE) || g_lines >= MAX_LINES) return;
    if (!g_looked) {
        g_looked = true;
        for (int i = 0; i < JOINTS; ++i) g_joint[i] = jointwriter::joint_by_name(player.transform, JOINT_NAMES[i]);
    }
    MO* camera = camera_transform();
    Vec3 eye{}, at{};
    Quat view{};
    if (camera == nullptr || !transform_position().value(camera, &eye, sizeof eye) ||
        !transform_rotation().value(camera, &view, sizeof view) || !transform_position().value(player.transform, &at, sizeof at)) return;
    Vec3 back = rotate(view, {0.0f, 0.0f, 1.0f});          // the camera looks along -Z: this is behind the view
    const float len = std::sqrt(back.x * back.x + back.z * back.z);
    if (len < 0.2f) return;                                 // looking straight up or down: no level direction
    back = {back.x / len, 0.0f, back.z / len};
    const Vec3 side{back.z, 0.0f, -back.x};
    for (int i = 0; i < JOINTS; ++i) {
        Vec3 p{};
        if (g_joint[i] == nullptr || !joint_position().value(g_joint[i], &p, sizeof p)) continue;
        const Vec3 d = p - eye;
        g_behind[i].add(d.x * back.x + d.z * back.z);
        g_side[i].add(d.x * side.x + d.z * side.z);
    }
    if (g_have_last) g_path_m += std::sqrt((at.x - g_last_at.x) * (at.x - g_last_at.x) + (at.z - g_last_at.z) * (at.z - g_last_at.z));
    g_last_at = at;
    g_have_last = true;

    const float now = now_s();
    if (g_window_at < 0.0f) g_window_at = now;
    if (now - g_window_at < WINDOW_S) return;
    bool worth = false;
    for (int i = 0; i < JOINTS; ++i) worth = worth || (g_behind[i].hi - g_behind[i].lo > WORTH_M);
    if (worth) {
        ++g_lines;
        const float cm = 100.0f;
        LOGI("%s lean: %.1f m/s%s%s | behind the eyes, cm: %s %.0f..%.0f, %s %.0f..%.0f, %s %.0f..%.0f | side: %s %.0f..%.0f", TAG,
             g_path_m / (now - g_window_at), bridge::flag(bridge::S_CUTSCENE) ? " CUTSCENE" : "",
             bridge::flag(bridge::S_CAN_USE_HANDS) ? "" : " game-motion",
             JOINT_SAY[0], g_behind[0].lo * cm, g_behind[0].hi * cm, JOINT_SAY[1], g_behind[1].lo * cm, g_behind[1].hi * cm,
             JOINT_SAY[2], g_behind[2].lo * cm, g_behind[2].hi * cm, JOINT_SAY[0], g_side[0].lo * cm, g_side[0].hi * cm);
    }
    for (int i = 0; i < JOINTS; ++i) { g_behind[i] = Range{}; g_side[i] = Range{}; }
    g_window_at = now;
    g_path_m = 0.0f;
}

} // namespace vr8::leanrec
