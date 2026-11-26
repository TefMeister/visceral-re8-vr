// leanfix.cpp -- see leanfix.h
#include "leanfix.h"

#include "base.h"
#include "bridge.h"
#include "jointwriter.h"
#include "leanmath.h"
#include "ready.h"

namespace vr8::leanfix {

namespace {
constexpr float LEVEL_MIN = 0.2f;          // the view this close to straight up or down: no level direction
constexpr float REPORT_EVERY_S = 10.0f;

leanmath::State g_state;
const leanmath::Numbers g_numbers;
Reading g_last;
unsigned g_generation = 0;
MO* g_neck = nullptr;
bool g_looked = false;
bool g_learned_told = false;
float g_peak = 0.0f, g_last_report = 0.0f;

Call& joint_position() { static Call c("via.Joint", "get_Position", 0); return c; }
Call& transform_position() { static Call c("via.Transform", "get_Position", 0); return c; }
Call& transform_rotation() { static Call c("via.Transform", "get_Rotation", 0); return c; }
} // namespace

const Reading& last() { return g_last; }

void pose() {
    g_last = Reading{};
    const float speed_mps = ready::pace().speed_mps, dt = ready::pace().dt;
    const auto& player = ready::now();
    if (player.generation != g_generation) {
        g_generation = player.generation;
        g_looked = false;
        g_state = leanmath::State{};           // a new player object: the standing distance is learned again
        g_learned_told = false;
    }
    const bool in_play = player.transform != nullptr && bridge::live() && bridge::flag(bridge::S_ACTIVE) &&
                         bridge::flag(bridge::S_TURN_OK);
    if (player.transform == nullptr || !bridge::live()) { bridge::write(bridge::S_LEAN, 0.0f); return; }
    if (!g_looked) {
        g_looked = true;
        g_neck = jointwriter::joint_by_name(player.transform, L"Neck_0");
    }
    MO* camera = ready::camera_transform();
    Vec3 eye{}, neck{};
    Quat view{};
    if (g_neck == nullptr || camera == nullptr || !transform_position().value(camera, &eye, sizeof eye) ||
        !transform_rotation().value(camera, &view, sizeof view) || !joint_position().value(g_neck, &neck, sizeof neck)) {
        leanmath::step(g_state, g_numbers, 0.0f, 0.0f, 0.0f, 0.0f, false, dt);
        bridge::write(bridge::S_LEAN, 0.0f);
        return;
    }
    const Vec3 back3 = rotate(view, {0.0f, 0.0f, 1.0f});          // the camera looks along -Z
    const float len = std::sqrt(back3.x * back3.x + back3.z * back3.z);
    if (len < LEVEL_MIN) {                                          // no level direction: hold what is asked
        bridge::write(bridge::S_LEAN, g_state.ask_m);
        return;
    }
    const Vec3 d = neck - eye;
    const float behind = (d.x * back3.x + d.z * back3.z) / len;
    const float down = std::clamp(back3.y, 0.0f, 1.0f);            // looking down tips "behind the view" upward
    const float applied = bridge::read(bridge::S_LEAN_APPLIED);
    const float ask = leanmath::step(g_state, g_numbers, behind, applied, down, speed_mps, in_play, dt);
    bridge::write(bridge::S_LEAN, ask);

    g_last = {true, behind, g_state.raw_m, g_state.learned ? g_state.standing_m : 0.0f, ask, applied, down};
    if (g_state.learned && !g_learned_told) {
        g_learned_told = true;
        LOGI("%s lean fix: standing, the neck is %.0f cm behind the eyes; leans are measured from here", TAG,
             g_state.standing_m * 100.0f);
    }
    g_peak = std::max(g_peak, ask);
    const float now = now_s();
    if (now - g_last_report >= REPORT_EVERY_S) {
        if (g_peak > 0.01f)
            LOGI("%s lean fix: up to %.0f cm asked in the last %.0f s (%s; standing %.0f cm)", TAG, g_peak * 100.0f,
                 REPORT_EVERY_S, applied > 0.0f ? "the body is moved" : "measuring only",
                 g_state.standing_m * 100.0f);
        g_peak = 0.0f;
        g_last_report = now;
    }
}

} // namespace vr8::leanfix
