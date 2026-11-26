// plugin.cpp -- Visceral RE8, rebuild 2 (started 2026-11-26): the frame. It only wires things together.
//
// From zero (Tefa, 2026-11-25): the game is the stock game + praydog's REFramework nightly + his VR layer; the mod
// is built again piece by piece as he plays, each piece to the rule set of the design note
// (modding-notes/2026-11-25d-clean-rebuild-2-design.md, section 5). b178's source (dev-archive/native) is the
// reference that is read; nothing of it is copied in whole.
//
// The frame's parts and the rule each one carries:
//   base         logging, maths, the checked calls into the game                     rule 6
//   switches     off.txt: every part can be switched off without a rebuild           rule 10
//   bridge       praydog's flags and the VR state, in from Lua (one float array)     design item 3
//   ready        the player and the one "the hands are the player's" flag            rules 7, 9
//   jointwriter  the only code that writes a joint; once per joint, fixed order      rules 1, 2, 3
// Features on it:
//   fingers      an empty hand's fingers stay still (2026-11-26)
//   bodyturn     the body no longer turns as one chunk with the head; the walk follows the head (2026-11-26)
//   sleephands   a hand whose controller fell asleep stays where it was (2026-11-26)
//   spinestill   the stomach no longer turns with the head (2026-11-26)
//   carryarms    the game's own arms held steady while Rose is carried (2026-11-26)
// Not built yet (each comes with the first feature that needs it): the object pool (rule 4), the request gate
// (rule 5), the arm-solver hook (rule 8), the recorders (Ghost Hand, the performance recorder).
//
// WHERE THINGS RUN, and nowhere else:
//   UpdateBehavior, pre        read the bridge, refresh the player              (game thread)
//   PrepareRendering, post     parts ask for joints, then the joint writer writes them
// Nothing of ours runs at BeginRendering (rule 1). ONE game function is hooked: bodyturn.cpp's.
#include "base.h"
#include "bodyturn.h"
#include "bridge.h"
#include "carryarms.h"
#include "fingers.h"
#include "jointwriter.h"
#include "ready.h"
#include "sleephands.h"
#include "spinestill.h"
#include "switches.h"

using namespace vr8;

namespace {
constexpr const char* SERIES = "rebuild 2";

void on_update() {
    if (switches::off("frame")) return;
    bridge::frame();
    ready::refresh();
    if (!switches::off("bodyturn")) bodyturn::frame();
}

void on_prepare_rendering() {
    if (switches::off("frame")) return;
    if (!switches::off("fingers")) fingers::pose();
    if (!switches::off("carryarms")) carryarms::pose();
    if (!switches::off("sleephands")) sleephands::pose();
    if (!switches::off("bodyturn") && !switches::off("spinestill")) spinestill::pose();
    jointwriter::flush();
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
    LOGI("%s loaded: %s, the frame + still fingers + carry arms + body turn + sleeping hands + still spine", TAG, SERIES);
    param->functions->on_pre_application_entry("UpdateBehavior", []() { on_update(); });
    param->functions->on_post_application_entry("PrepareRendering", []() { on_prepare_rendering(); });
    return true;
}
