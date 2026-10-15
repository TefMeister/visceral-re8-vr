// plugin.cpp -- Visceral RE8: Andyalpa's "Hands Off" pack for Resident Evil Village, ported to C++ (started 2026-10-15).
//
// Tefa, 2026-10-15: Andyalpa does not want to mod Village, so the pack becomes Visceral RE8, in C++, the way
// visceral-re2-vr's native code is built. The pack's Lua is kept untouched in dev-archive/original-lua/ as the
// reference; each file is ported here one at a time while the unported ones keep running as Lua beside it.
// praydog's re8_vr.lua (the Village VR layer itself) stays Lua; our copy only gains stand-down switches.
// This file only wires things together; every feature lives in its own file.
//
// Ported so far:
//   haptics.cpp  re8_vr_haptics.lua: the game's rumble on the controllers, left hand only when it supports the gun,
//                strength scale, full-auto pulses
//   recoil.cpp   re8_vr_recoil.lua: physical recoil on the hands (spring, per-weapon intensity, one/two hands)
//                (player.cpp finds the player objects the way praydog's RE8VR.cpp does; json_mini.cpp reads the saved file)
#include <windows.h>

#include <atomic>

#include "bridge.h"
#include "common.h"
#include "haptics.h"
#include "player.h"
#include "recoil.h"

using namespace vn;

namespace {
void on_frame() {
    static std::atomic<bool> installed{false};
    if (!installed.exchange(true)) { bridge::install(); haptics::install(); recoil::install(); }   // hooks need the type database: first game frame
    bridge::frame_begin();
    player::refresh();                                 // before any feature: the hooks later in the frame read this snapshot
    haptics::frame();
    recoil::frame();
}
} // namespace

extern "C" __declspec(dllexport) void reframework_plugin_required_version(REFrameworkPluginVersion* version) {
    version->major = REFRAMEWORK_PLUGIN_VERSION_MAJOR;
    version->minor = REFRAMEWORK_PLUGIN_VERSION_MINOR;
    version->patch = REFRAMEWORK_PLUGIN_VERSION_PATCH;
}

extern "C" __declspec(dllexport) bool reframework_plugin_initialize(const REFrameworkPluginInitializeParam* param) {
    g_param = param;
    try {
        API::initialize(param);
    } catch (...) {
        param->functions->log_error("%s API init failed, nothing will run", TAG);
        return true;
    }
    param->functions->log_info("%s loaded: Hands Off port, haptics + recoil", TAG);
    // the bridge Lua writes its readings at UpdateHID pre; reading after it, at UpdateBehavior pre, sees this frame's
    param->functions->on_pre_application_entry("UpdateBehavior", []() { on_frame(); });
    // re8_vr_recoil.lua stepped its spring at both of these (once per frame, whichever comes first)
    param->functions->on_pre_application_entry("UpdateMotion", []() { recoil::physics_point(); });
    param->functions->on_pre_application_entry("LateUpdateBehavior", []() { recoil::physics_point(); });
    return true;
}
