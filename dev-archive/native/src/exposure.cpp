// exposure.cpp -- the game's automatic brightness ("adaptive lighting", eye adaptation) switched off (2026-10-29, Fable;
// Tefa: "remove the adaptive lighting from RE8 and 3"). Ported from Visceral RE2's exposure.cpp (2026-10-28, b180/b192),
// brightness part only: the colour-grading and contrast switches RE2 grew the same night are not asked for here.
//
// What RE2 found live [verified-live 2026-10-28, RE2, n=1]: the main camera (via.SceneManager -> MainView -> PrimaryCamera)
// carries a via.render.ToneMapping whose AutoExposure is Enable (0), adapting between AutoExposureMinEV / MaxEV (-8 / +16)
// around the area's authored EV. The game's own tone-map controller copies its blended parameters (AutoExposure = Enable)
// onto that component in its late update, so a one-off write is undone the next frame. Two things, written every frame
// at BeginRendering pre (after the game's late update, before the frame is drawn):
//   1. AutoExposure = Disable. Which number is Disable: the enum's names are Disable / Enable / FixedEnable; Enable = 0.
//      The other two are tried at start: the first value after which get_UseAutoExposure reads false is kept and logged.
//   2. AutoExposureMinEV and MaxEV pinned to the area's own EV. The controller never writes the limits, so this holds even
//      while the game has the adaptation switched back on (RE2 in the headset: the Disable write alone did not stop it).
// Village and RE3 are NOT checked yet: every claim above is RE2's until this plugin's log says "kept off" with
// UseAutoExposure 0 and a steady EV. [compile-verified] at most until it has run.
//
// On by default. Off when: the Lua menu's tick box says so (bridge slot S_AUTO_EXPOSURE_ON = 1), or NUM7 toggles it (logged).
#include "exposure.h"
#include "bridge.h"
#include "common.h"
#include <windows.h>

using namespace vn;

namespace {

constexpr int AE_ENABLE = 0;              // via.render.ToneMapping.AutoExposure.Enable [verified-live 2026-10-28, RE2]
constexpr int AE_CANDIDATES[] = {2, 1};   // Disable is one of these; FixedEnable the other [inferred-static: Vignetting's Disable = 2]
constexpr float REPORT_S = 10.0f;
constexpr float GAME_MIN_EV = -8.0f, GAME_MAX_EV = 16.0f;   // the limits the game leaves on the component (RE2, read live), put back when ours is off

struct State {
    int disable_value = -1;            // learned: the value that makes get_UseAutoExposure false
    bool tried[3] = {false, false, false};
    bool off = true;                   // our switch: true = auto exposure kept off
    bool key7 = false;
    bool limits_pinned = false;        // we have the adaptation limits pinned (so they are put back once)
    MO* last_tm = nullptr;
    int writes = 0;
    float last_report = 0.0f;
} g;

MO* main_camera_go() {
    static API::Method* main_view = API::get()->tdb()->find_method("via.SceneManager", "get_MainView");
    static API::Method* primary = API::get()->tdb()->find_method("via.SceneView", "get_PrimaryCamera");
    void* sm = API::get()->get_native_singleton("via.SceneManager");
    if (main_view == nullptr || primary == nullptr || sm == nullptr) return nullptr;
    auto* ctx = API::get()->get_vm_context();
    void* view = main_view->call<void*>(ctx, sm);
    auto* cam = view != nullptr ? (MO*)primary->call<void*>(ctx, view) : nullptr;
    return cam != nullptr ? call_ptr(cam, "get_GameObject") : nullptr;
}

void set_float(MO* o, const char* name, float v) {
    auto* m = o ? find_method_deep(o->get_type_definition(), name) : nullptr;
    if (m != nullptr) m->call<void>(API::get()->get_vm_context(), (void*)o, v);
}
void set_ae(MO* tm, int v) {
    static API::Method* m = API::get()->tdb()->find_method("via.render.ToneMapping", "setAutoExposure");
    if (m != nullptr) m->call<void>(API::get()->get_vm_context(), (void*)tm, v);
}
int get_ae(MO* tm) {
    static API::Method* m = API::get()->tdb()->find_method("via.render.ToneMapping", "getAutoExposure");
    return m != nullptr ? m->call<int>(API::get()->get_vm_context(), (void*)tm) : -1;
}
bool use_ae(MO* tm) { return call_direct<bool>(tm, "get_UseAutoExposure", true); }

float now_s() {
    static const DWORD t0 = GetTickCount();
    return (GetTickCount() - t0) / 1000.0f;
}

}  // namespace

namespace vn::exposure {

void render_point() {
    const bool k7 = (GetAsyncKeyState(VK_NUMPAD7) & 0x8000) != 0;
    if (k7 && !g.key7) { g.off = !g.off; LOGI("%s exposure: NUM7 -> the game's automatic brightness %s", TAG, g.off ? "OFF (ours)" : "ON (the game's own)"); }
    g.key7 = k7;
    const float menu = bridge::view(bridge::S_AUTO_EXPOSURE_ON);
    const bool keep_off = g.off && !(menu > 0.5f && menu < bridge::NO_VALUE - 1.0f);

    MO* cam_go = main_camera_go();
    if (cam_go == nullptr) return;
    MO* tm = component(cam_go, "via.render.ToneMapping");
    if (tm == nullptr) return;
    if (tm != g.last_tm) { g.last_tm = tm; g.limits_pinned = false; LOGI("%s exposure: main camera ToneMapping %p: AutoExposure %d, UseAutoExposure %d", TAG, (void*)tm, get_ae(tm), (int)use_ae(tm)); }
    if (!keep_off) {   // the game's own value stands (its controller writes Enable every frame); its limits come back once
        if (g.limits_pinned) { set_float(tm, "set_AutoExposureMinEV", GAME_MIN_EV); set_float(tm, "set_AutoExposureMaxEV", GAME_MAX_EV); g.limits_pinned = false; }
        return;
    }
    // the adaptation's limits pinned to the area's own EV, so it cannot move even while the game has it on
    const float ev = call_direct<float>(tm, "get_EV", 0.0f);
    set_float(tm, "set_AutoExposureMinEV", ev);
    set_float(tm, "set_AutoExposureMaxEV", ev);
    g.limits_pinned = true;

    if (g.disable_value < 0) {
        for (int v : AE_CANDIDATES) {
            if (g.tried[v]) continue;
            g.tried[v] = true;
            set_ae(tm, v);
            const bool still = use_ae(tm);
            LOGI("%s exposure: tried AutoExposure %d: reads back %d, UseAutoExposure %d", TAG, v, get_ae(tm), (int)still);
            if (!still) { g.disable_value = v; LOGI("%s exposure: Disable = %d, kept: the game's automatic brightness is OFF", TAG, v); }
            break;   // one try per frame
        }
        if (g.disable_value < 0 && g.tried[1] && g.tried[2]) {
            g.disable_value = AE_CANDIDATES[0];
            LOGW("%s exposure: neither value read back as off; keeping %d anyway", TAG, g.disable_value);
        }
        return;
    }
    set_ae(tm, g.disable_value);
    ++g.writes;
    const float t = now_s();
    if (t - g.last_report >= REPORT_S) {
        g.last_report = t;
        LOGI("%s exposure: kept off (%d writes; AutoExposure %d, UseAutoExposure %d, EV %.2f, limits %.2f..%.2f)", TAG, g.writes, get_ae(tm),
             (int)use_ae(tm), call_direct<float>(tm, "get_EV", -99.0f), call_direct<float>(tm, "get_AutoExposureMinEV", -99.0f),
             call_direct<float>(tm, "get_AutoExposureMaxEV", -99.0f));
    }
}

}  // namespace vn::exposure
