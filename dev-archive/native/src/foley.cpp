// foley.cpp -- see foley.h
#include "foley.h"
#include "common.h"
#include "gate.h"

namespace vn::foley {

namespace {
int g_silenced = 0;

bool silent_motion(uint32_t id) { return (id >= 2100 && id <= 2399) || id == 2421; }   // ready / aim / lowered (as the scope mod)

// 2026-11-06 (Tefa: "hand on the hammer works, but after a shot with rt, the click sound of the drum turning still plays"): with the
// palm on the hammer the shot motion's foley (24xx: the thumb cocking, the drum turning) is skipped too; LT plays our own cock
// sound. [hypothesis] the gunshot itself is the weapon's own sound, not this foley: if the shot goes quiet, this is why.
bool shot_motion(uint32_t id) { return id >= 2400 && id <= 2499; }

int pre(int argc, void** argv, int layer_at) {
    const bool held = gate::holding(), hammer = gate::on_hammer();
    if ((!held && !hammer) || argc <= layer_at || argv[layer_at] == nullptr) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    auto* layer = (MO*)argv[layer_at];
    if (!is_managed(layer)) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    const uint32_t id = call_direct<uint32_t>(layer, "get_MotionID", 0u);
    if (!((held && silent_motion(id)) || (hammer && shot_motion(id)))) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    if (++g_silenced <= 20 || g_silenced % 100 == 0)
        LOGI("%s foley: %s: the game's handling click of motion %u silenced (#%d)", TAG, held ? "the Wolfsbane is in the left hand" : "the palm is on the hammer", id, g_silenced);
    return REFRAMEWORK_HOOK_SKIP_ORIGINAL;
}
// weaponTrigger(GameObject, TreeLayer, tracks, UInt32): the layer is argv[3]; manualTrigger(TreeLayer, tracks, UInt32): argv[2]
int pre_weapon(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) { return pre(argc, argv, 3); }
int pre_manual(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) { return pre(argc, argv, 2); }
} // namespace

void install() {
    auto* td = API::get()->tdb()->find_type("app.WwiseWeaponMotionSequence");
    if (td == nullptr) { LOGW("%s foley: app.WwiseWeaponMotionSequence NOT FOUND: the handling clicks stay", TAG); return; }
    int n = 0;
    for (auto* m : td->get_methods()) {
        if (m == nullptr) continue;
        const std::string name = m->get_name();
        if (name == "weaponTrigger") { m->add_hook(pre_weapon, nullptr, false); ++n; }
        else if (name == "manualTrigger") { m->add_hook(pre_manual, nullptr, false); ++n; }
    }
    LOGI("%s foley: hooked %d handling-sound trigger(s): the raise / lower clicks are quiet while the Wolfsbane is in the left hand", TAG, n);
}

} // namespace vn::foley
