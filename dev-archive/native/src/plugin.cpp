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
#include "forearm.h"
#include "righthand.h"
#include "pumpbolt.h"
#include "nodock.h"
#include "breech.h"
#include "gate.h"
#include "lookup.h"
#include "dryfire.h"
#include "eject.h"
#include "foley.h"
#include "bridge.h"
#include "common.h"
#include "haptics.h"
#include "ghosthand.h"
#include "handstate.h"
#include "ik.h"
#include "player.h"
#include "pairs.h"
#include "rack.h"
#include "rack_right.h"
#include "equipguard.h"
#include "smooth.h"
#include "recoil.h"
#include "reload.h"
#include "magdisp.h"
#include "zones.h"
#include "weapons.h"
#include "exposure.h"
#include "perfprobe.h"
#include "shellclip.h"
#include "timings.h"
#include "dockreport.h"
#include "menukey.h"

using namespace vn;

namespace {
void on_frame() {
    perfprobe::frame();                                // 2026-11-02: the performance recorder counts every game frame (perfprobe.h)
    static std::atomic<bool> installed{false};
    if (!installed.exchange(true)) { bridge::install(); haptics::install(); recoil::install(); reload::install(); eject::install(); foley::install(); ik::install(); body::install(); nodock::install(); equipguard::install(); player::probe_types(); body::probe_types(); }   // hooks need the type database: first game frame
    bridge::frame_begin();
    menukey::frame();                                  // 2026-11-04: the Emporium's kitchen card opens REFramework's menu (menukey.h)
    player::refresh();                                 // before any feature: the hooks later in the frame read this snapshot
    haptics::frame();
    weapons::watch();
    zones::frame();
    reload::frame();
    breech::frame();
    gate::frame();
    lookup::frame();                                   // 2026-11-02: our own read-only look at the game's type list (lookup.h)                                     // 2026-11-01: the Wolfsbane loaded by the right hand (after breech: right B)
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
    shellclip::frame();      // 2026-11-02: the test file for the shell-in finger clip (shellclip.h)
    timings::frame();        // 2026-11-07: the named seconds, re-read when timings.json changes (timings.h)
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
    perfprobe::start();                                // 2026-11-02: always-on performance recorder, its own thread (perfprobe.h)
    param->functions->on_present([]() { perfprobe::present(); });
    // the bridge Lua writes its readings at UpdateHID pre; reading after it, at UpdateBehavior pre, sees this frame's
    param->functions->on_pre_application_entry("UpdateBehavior", []() { on_frame(); });
    // the ammo counter is placed at the right hand just before it is drawn (re8_vr_ammo_hud.lua did the same)
    param->functions->on_pre_gui_draw_element([](void* element, void* context) { return ammo_hud::pre_gui_draw(element, context); });
    // re8_vr_recoil.lua stepped its spring at both of these (once per frame, whichever comes first)
    param->functions->on_pre_application_entry("UpdateMotion", []() { recoil::physics_point(); });
    param->functions->on_pre_application_entry("LateUpdateBehavior", []() { recoil::physics_point(); });
    // the gun's joints (magazine, slide) after its own animation, and again before drawing (the engine rewrites them)
    param->functions->on_post_application_entry("LateUpdateBehavior", []() { body::late_point(); reload::late_point(); magdisp::point(); rack::late_point(); pumpbolt::point(); rack_right::late_point(); breech::pose_point(); gate::late_point(); });
    param->functions->on_post_application_entry("PrepareRendering", []() { body::render_point(); righthand::render_point(); fingers::render_point(); forearm::render_point();   /* 2026-11-02: the still hands first, the opening hand on top */ reload::render_point(); magdisp::point(); rack::render_point(); pumpbolt::point(); rack_right::render_point(); breech::pose_point(); gate::late_point(); ghosthand::render_point(); shellclip::render_point(); });
    param->functions->on_pre_application_entry("BeginRendering", []() { exposure::render_point(); reload::render_point(); magdisp::point(); rack::begin_render_point(); pumpbolt::point(); rack_right::begin_render_point(); breech::pose_point(); gate::late_point(); righthand::begin_render(); fingers::begin_render(); forearm::begin_render(); body::begin_render(); shellclip::begin_render();  dockreport::render_point();   /* 2026-11-04: where the docked left hand lands, measured */ });
    return true;
}
