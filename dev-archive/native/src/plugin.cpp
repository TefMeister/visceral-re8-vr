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
// Moved over from the RE7 RELOADED mod (2026-10-18):
//   reload.cpp   magazines and single rounds by hand, the ammo pouch on the left hip (Andyalpa's ammo_left spot)
//   rack.cpp     slide / bolt / pump racking with the left hand held on the gun
//   ik.cpp       the AnimIK2Bone.calc hook recoil and the rack share     weapons.cpp  the Village weapon list
//   handstate.cpp  what each hand is doing, for the hand poses
#include <windows.h>

#include <atomic>

#include "ammo_hud.h"
#include "body.h"
#include "turn.h"
#include "gunreport.h"
#include "fingers.h"
#include "nodock.h"
#include "breech.h"
#include "dryfire.h"
#include "eject.h"
#include "bridge.h"
#include "common.h"
#include "haptics.h"
#include "ghosthand.h"
#include "handstate.h"
#include "ik.h"
#include "player.h"
#include "pairs.h"
#include "rack.h"
#include "equipguard.h"
#include "smooth.h"
#include "recoil.h"
#include "reload.h"
#include "zones.h"
#include "weapons.h"
#include "exposure.h"

using namespace vn;

namespace {
void on_frame() {
    static std::atomic<bool> installed{false};
    if (!installed.exchange(true)) { bridge::install(); haptics::install(); recoil::install(); reload::install(); eject::install(); ik::install(); body::install(); nodock::install(); equipguard::install(); player::probe_types(); body::probe_types(); }   // hooks need the type database: first game frame
    bridge::frame_begin();
    player::refresh();                                 // before any feature: the hooks later in the frame read this snapshot
    haptics::frame();
    weapons::watch();
    zones::frame();
    reload::frame();
    breech::frame();
    rack::frame();
    dryfire::frame();                                  // 2026-10-30: the empty click on RT (after reload + rack: they say if it fires)
    smooth::publish_zone();                            // the FRONT GRIP zone, after rack (zones.h GRIP)
    pairs::frame();                                    // the numbered hand pairs, after rack (pairs.h): the slide / bolt takes an LG first
    ammo_hud::frame();
    recoil::frame();
    handstate::frame();
    turn::frame();           // 2026-10-29: the game's own body-follow rule, with Tefa's numbers
    gunreport::frame();      // 2026-10-29: the gun's place in the hand, written down (the "gun too low, swings like a pendulum" launches)
    body::frame();
    fingers::frame();
    nodock::frame();
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
    param->functions->log_info("%s loaded: Hands Off port, haptics + recoil + manual reloads", TAG);
    // the bridge Lua writes its readings at UpdateHID pre; reading after it, at UpdateBehavior pre, sees this frame's
    param->functions->on_pre_application_entry("UpdateBehavior", []() { on_frame(); });
    // the ammo counter is placed at the right hand just before it is drawn (re8_vr_ammo_hud.lua did the same)
    param->functions->on_pre_gui_draw_element([](void* element, void* context) { return ammo_hud::pre_gui_draw(element, context); });
    // re8_vr_recoil.lua stepped its spring at both of these (once per frame, whichever comes first)
    param->functions->on_pre_application_entry("UpdateMotion", []() { recoil::physics_point(); });
    param->functions->on_pre_application_entry("LateUpdateBehavior", []() { recoil::physics_point(); });
    // the gun's joints (magazine, slide) after its own animation, and again before drawing (the engine rewrites them)
    param->functions->on_post_application_entry("LateUpdateBehavior", []() { body::late_point(); reload::late_point(); rack::late_point(); });
    param->functions->on_post_application_entry("PrepareRendering", []() { body::render_point(); fingers::render_point(); reload::render_point(); rack::render_point(); ghosthand::render_point(); });
    param->functions->on_pre_application_entry("BeginRendering", []() { exposure::render_point(); reload::render_point(); rack::begin_render_point(); fingers::begin_render(); body::begin_render(); });
    return true;
}
