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
//   gamearms     decides "the game's own arms are showing" (Rose); the scene list (2026-11-26, was a script)
//   gate         THE REQUEST GATE: the only code that asks the game to start or switch something   rule 5
//   doors        a hand on a door opens it, never from afar; with Rose, walking in does (2026-11-26)
//   doorsounds   which of a door's ten sounds play; the first "partly open" one muted (2026-11-26)
//   leanfix      the body at a stop: measures the neck against the eyes as drawn; moves the body only when
//                bodyplace.json says "lean": 1 (2026-11-26, RE8-092)
//   rec          THE RECORDERS: Camera Jitter BeG0nE, Ghost Hand BeG0nE, the walk file (2026-11-26, RE8-091)
// Not built yet (each comes with the first feature that needs it): the object pool (rule 4), the arm-solver
// hook (rule 8), the recorders (Ghost Hand, the performance recorder).
//
// WHERE THINGS RUN, and nowhere else:
//   UpdateBehavior, pre        read the bridge, refresh the player, the request gate, the parts' frame steps
//   PrepareRendering, post     parts ask for joints, then the joint writer writes them
//   LockScene, post            gamearms: the body's draw flag (after the loader's own hiding)
// Nothing of ours runs at BeginRendering (rule 1). FOUR game functions are hooked: bodyturn.cpp's (the body's
// direction), doors.cpp's (the walk-in open) and doorsounds.cpp's two (the door's sound call); the last three
// only read a flag or their own argument and count (rule 8).
#include "base.h"
#include "bodyturn.h"
#include "bridge.h"
#include "carryarms.h"
#include "doors.h"
#include "doorsounds.h"
#include "fingers.h"
#include "gamearms.h"
#include "gate.h"
#include "jointwriter.h"
#include "leanfix.h"
#include "leanrec.h"
#include "ready.h"
#include "rec.h"
#include "sleephands.h"
#include "spinestill.h"
#include "switches.h"

using namespace vr8;

namespace {
constexpr const char* SERIES = "rebuild 2";

// off.txt's `frame` switches every part off, but not the two readers below and not the recorders: they change
// nothing in the game, and the bare base must be measurable (the legs' halving test, 2026-11-26).
void on_update() {
    bridge::frame();
    ready::refresh();
    if (switches::off("frame")) return;
    if (!switches::off("gamearms")) gamearms::frame();
    gate::run();                                   // what the parts asked for last frame is made here, only here
    if (!switches::off("doorsounds")) doorsounds::frame();
    if (!switches::off("doors")) doors::frame();
    if (!switches::off("bodyturn")) bodyturn::frame();
}

void measure() {                                   // after the joints are written: the body as it is drawn
    ready::render_tick();
    if (!switches::off("frame") && !switches::off("leanfix")) leanfix::pose();
    else bridge::write(bridge::S_LEAN, 0.0f);
    if (!switches::off("recorders")) rec::pose();
}

void on_prepare_rendering() {
    if (switches::off("frame")) { measure(); return; }
    if (!switches::off("fingers")) fingers::pose();
    if (!switches::off("carryarms")) carryarms::pose();
    if (!switches::off("sleephands")) sleephands::pose();
    if (!switches::off("bodyturn") && !switches::off("spinestill")) spinestill::pose();
    if (!switches::off("doors")) doors::pose();
    if (!switches::off("leanrec")) leanrec::pose();   // dev only: measures, changes nothing
    jointwriter::flush();
    measure();
}

void on_lock_scene() {
    if (switches::off("frame") || switches::off("gamearms")) return;
    gamearms::lock_scene();
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
    LOGI("%s loaded: %s, the frame + still fingers + carry arms + body turn + sleeping hands + still spine + game arms + doors by hand + the recorders + the lean fix (measuring)", TAG, SERIES);
    param->functions->on_pre_application_entry("UpdateBehavior", []() { on_update(); });
    param->functions->on_post_application_entry("PrepareRendering", []() { on_prepare_rendering(); });
    param->functions->on_post_application_entry("LockScene", []() { on_lock_scene(); });
    return true;
}
