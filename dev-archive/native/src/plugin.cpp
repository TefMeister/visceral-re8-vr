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
#include "torch.h"
#include "turn.h"
#include "gunreport.h"
#include "fingers.h"
#include "forearm.h"
#include "armstretch.h"
#include "sleephands.h"
#include "doors.h"
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
#include "accuracy.h"
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

// b175 (2026-11-25, the lift glitch hunt: Duke drawn frozen with our plugin loaded, moving without it): any part named in
// reframework/data/visceral_re8/off.txt (names as below: reload, breech, doors, nodock ...; one per line or space-separated) is not
// installed and not run. Read once, at the first call. No file = everything on, as before. For finding which part breaks something
// with one launch per guess and no rebuild; never shipped with a file in place.
#include <fstream>
#include <set>
#include <string>
namespace {
const std::set<std::string>& off_set() {
    static std::set<std::string> s;
    static bool read = false;
    if (!read) {
        read = true;
        wchar_t exe[MAX_PATH]{};
        GetModuleFileNameW(nullptr, exe, MAX_PATH);
        std::wstring path(exe);
        path = path.substr(0, path.find_last_of(L"\\/") + 1) + L"reframework\\data\\visceral_re8\\off.txt";
        std::ifstream f(path);
        std::string w, all;
        while (f >> w) { if (!w.empty() && w[0] != '#') { s.insert(w); all += w + " "; } }
        if (!s.empty()) LOGI("%s OFF (off.txt): %s", TAG, all.c_str());
    }
    return s;
}
bool off(const char* part) { return off_set().count(part) != 0; }
} // namespace

namespace {
void on_frame() {
    if (!off("perfprobe")) perfprobe::frame();                                // 2026-11-02: the performance recorder counts every game frame (perfprobe.h)
    static std::atomic<bool> installed{false};
    if (!installed.exchange(true)) { if (!off("bridge")) bridge::install(); if (!off("haptics")) haptics::install(); if (!off("recoil")) recoil::install(); if (!off("reload")) reload::install(); if (!off("accuracy")) accuracy::install(); if (!off("eject")) eject::install(); if (!off("foley")) foley::install(); if (!off("ik")) ik::install(); if (!off("body")) body::install(); if (!off("nodock")) nodock::install(); if (!off("equipguard")) equipguard::install(); if (!off("player")) player::probe_types(); if (!off("body")) body::probe_types(); }   // hooks need the type database: first game frame
    if (!off("bridge")) bridge::frame_begin();
    if (!off("menukey")) menukey::frame();                                  // 2026-11-04: the Emporium's kitchen card opens REFramework's menu (menukey.h)
    if (!off("player")) player::refresh();                                 // before any feature: the hooks later in the frame read this snapshot
    if (!off("haptics")) haptics::frame();
    if (!off("weapons")) weapons::watch();
    if (!off("zones")) zones::frame();
    if (!off("reload")) reload::frame();
    if (!off("accuracy")) accuracy::frame();       // 2026-11-11: a handgun's accuracy from the hold and the movement (accuracy.h)
    if (!off("breech")) breech::frame();
    if (!off("gate")) gate::frame();
    if (!off("lookup")) lookup::frame();                                   // 2026-11-02: our own read-only look at the game's type list (lookup.h)                                     // 2026-11-01: the Wolfsbane loaded by the right hand (after breech: right B)
    if (!off("rack")) rack::frame();
    if (!off("dryfire")) dryfire::frame();                                  // 2026-10-30: the empty click on RT (after reload + rack: they say if it fires)
    if (!off("smooth")) smooth::publish_zone();                            // the FRONT GRIP zone, after rack (zones.h GRIP)
    if (!off("torch")) torch::frame();                                    // 2026-11-12: the torch you hold (torch.h), before handstate reads it
    if (!off("pairs")) pairs::frame();                                    // the numbered hand pairs, after rack (pairs.h): the slide / bolt takes an LG first
    if (!off("ammo_hud")) ammo_hud::frame();
    if (!off("recoil")) recoil::frame();
    if (!off("handstate")) handstate::frame();
    if (!off("turn")) turn::frame();           // 2026-10-29: the game's own body-follow rule, with Tefa's numbers
    if (!off("sleephands")) sleephands::frame();     // 2026-11-09: a sleeping controller lowers its hand to the side
    if (!off("doors")) doors::frame();          // 2026-11-18: doors and gates pushed by the hand and the body (doors.h)
    if (!off("gunreport")) gunreport::frame();      // 2026-10-29: the gun's place in the hand, written down (the "gun too low, swings like a pendulum" launches)
    if (!off("body")) body::frame();
    if (!off("fingers")) fingers::frame();
    if (!off("nodock")) nodock::frame();
    if (!off("shellclip")) shellclip::frame();      // 2026-11-02: the test file for the shell-in finger clip (shellclip.h)
    if (!off("timings")) timings::frame();        // 2026-11-07: the named seconds, re-read when timings.json changes (timings.h)
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
    if (!off("perfprobe")) perfprobe::start();                                // 2026-11-02: always-on performance recorder, its own thread (perfprobe.h)
    param->functions->on_present([]() { if (!off("perfprobe")) perfprobe::present(); });
    // the bridge Lua writes its readings at UpdateHID pre; reading after it, at UpdateBehavior pre, sees this frame's
    param->functions->on_pre_application_entry("UpdateBehavior", []() { on_frame(); });
    // the ammo counter is placed at the right hand just before it is drawn (re8_vr_ammo_hud.lua did the same)
    param->functions->on_pre_gui_draw_element([](void* element, void* context) { return off("ammo_hud") ? true : ammo_hud::pre_gui_draw(element, context); });
    // re8_vr_recoil.lua stepped its spring at both of these (once per frame, whichever comes first)
    param->functions->on_pre_application_entry("UpdateMotion", []() { if (!off("recoil")) recoil::physics_point(); });
    param->functions->on_pre_application_entry("LateUpdateBehavior", []() { if (!off("recoil")) recoil::physics_point(); });
    // the gun's joints (magazine, slide) after its own animation, and again before drawing (the engine rewrites them)
    param->functions->on_post_application_entry("LateUpdateBehavior", []() { if (off("phase_late")) return; if (!off("body")) body::late_point(); if (!off("reload")) reload::late_point(); if (!off("magdisp")) magdisp::point(); if (!off("rack")) rack::late_point(); if (!off("pumpbolt")) pumpbolt::point(); if (!off("rack_right")) rack_right::late_point(); if (!off("breech")) breech::pose_point(); if (!off("gate")) gate::late_point(); if (!off("doors")) doors::late_point(); });
    param->functions->on_post_application_entry("PrepareRendering", []() { if (off("phase_prepare")) return; if (!off("body")) body::render_point(); if (!off("righthand")) righthand::render_point(); if (!off("fingers")) fingers::render_point(); if (!off("forearm")) forearm::render_point();   /* 2026-11-02: the still hands first, the opening hand on top */ if (!off("reload")) reload::render_point(); if (!off("magdisp")) magdisp::point(); if (!off("rack")) rack::render_point(); if (!off("pumpbolt")) pumpbolt::point(); if (!off("rack_right")) rack_right::render_point(); if (!off("breech")) breech::pose_point(); if (!off("gate")) gate::late_point(); if (!off("ghosthand")) ghosthand::render_point(); if (!off("shellclip")) shellclip::render_point(); if (!off("armstretch")) armstretch::render_point();   /* 2026-11-08: last: the rubber left arm */ });
    param->functions->on_pre_application_entry("BeginRendering", []() { if (off("phase_begin")) return; if (!off("exposure")) exposure::render_point(); if (!off("reload")) reload::render_point(); if (!off("magdisp")) magdisp::point(); if (!off("rack")) rack::begin_render_point(); if (!off("pumpbolt")) pumpbolt::point(); if (!off("rack_right")) rack_right::begin_render_point(); if (!off("breech")) breech::pose_point(); if (!off("gate")) gate::late_point(); if (!off("righthand")) righthand::begin_render(); if (!off("fingers")) fingers::begin_render(); if (!off("forearm")) forearm::begin_render(); if (!off("body")) body::begin_render(); if (!off("shellclip")) shellclip::begin_render(); if (!off("armstretch")) armstretch::begin_render();  if (!off("dockreport")) dockreport::render_point();   /* 2026-11-04: where the docked left hand lands, measured */ if (!off("doors")) doors::render_point(); });
    return true;
}
