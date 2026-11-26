// ready.cpp -- see ready.h
#include "ready.h"

#include "bridge.h"

namespace vr8::ready {

namespace {
Snapshot g_now;
MO* g_last_player = nullptr;
unsigned g_generation = 0;
} // namespace

void refresh() {
    Snapshot s;
    auto* props = API::get()->get_managed_singleton("app.PropsManager");
    s.player = field_obj(props, "<Player>k__BackingField");
    if (s.player != g_last_player) {
        g_last_player = s.player;
        ++g_generation;
        LOGI("%s ready: the player is %s (generation %u)", TAG, s.player != nullptr ? "here" : "gone", g_generation);
    }
    s.generation = g_generation;
    if (s.player != nullptr) {
        static Call get_transform("via.GameObject", "get_Transform", 0);
        s.transform = get_transform.ptr(s.player);
    }
    s.hands_are_players = s.transform != nullptr && bridge::live() && bridge::flag(bridge::S_ACTIVE) &&
                          !bridge::flag(bridge::S_CUTSCENE) && bridge::flag(bridge::S_CAN_USE_HANDS);
    g_now = s;
}

const Snapshot& now() { return g_now; }

namespace {
Pace g_pace;
float g_pace_at = -1.0f;
unsigned g_pace_generation = 0;
constexpr float PACE_JUMP_M = 0.5f;      // further than this in one picture: a load or a teleport, not a speed
} // namespace

void render_tick() {
    static Call position("via.Transform", "get_Position", 0);
    static Call rotation("via.Transform", "get_Rotation", 0);
    const float now = now_s();
    Pace p;
    p.dt = g_pace_at < 0.0f ? 0.011f : std::fmin(0.1f, std::fmax(0.0005f, now - g_pace_at));
    g_pace_at = now;
    if (g_now.transform != nullptr && position.value(g_now.transform, &p.at, sizeof p.at) &&
        rotation.value(g_now.transform, &p.turn, sizeof p.turn)) {
        p.ok = true;
        if (g_pace.ok && g_pace_generation == g_now.generation) {
            const float dx = p.at.x - g_pace.at.x, dz = p.at.z - g_pace.at.z;
            const float went = std::sqrt(dx * dx + dz * dz);
            p.speed_mps = went < PACE_JUMP_M ? went / p.dt : 0.0f;
        }
    }
    g_pace_generation = g_now.generation;
    g_pace = p;
}

const Pace& pace() { return g_pace; }

MO* camera_transform() {
    static Call main_view("via.SceneManager", "get_MainView", 0);
    static Call primary_camera("via.SceneView", "get_PrimaryCamera", 0);
    static Call object_transform("via.GameObject", "get_Transform", 0);
    MO* view = main_view.ptr(API::get()->get_native_singleton("via.SceneManager"));
    MO* camera = primary_camera.ptr(view);
    return object_transform.ptr(dyn_ptr(camera, "get_GameObject"));
}

} // namespace vr8::ready
