// ik.cpp -- see ik.h
#include "ik.h"
#include "common.h"
#include "dockpose.h"
#include "player.h"
#include "rack.h"
#include "rack_right.h"
#include "recoil.h"
#include "reload.h"
#include "smooth.h"

namespace vn::ik {

namespace {
int pre_calc(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    if (argc < 2 || argv[1] == nullptr) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    auto* ik = (MO*)argv[1];
    const auto& s = player::now();
    if (ik != s.ik_right && ik != s.ik_left) return REFRAMEWORK_HOOK_CALL_ORIGINAL;   // not a player hand
    recoil::on_ik(ik);
    reload::on_ik(ik);
    rack::on_ik(ik);
    smooth::on_ik(ik);   // eases the left hand when whoever places it changes
    dockpose::on_ik(ik); // (2026-10-28): the docked spot's wrist from Dock Poser, eased on its own
    rack_right::on_ik(ik); // LAST (2026-11-01): the right hand on the bolt, the left hand holding the front
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}
} // namespace

void install() {
    auto* m = API::get()->tdb()->find_method("app.AnimIK2Bone", "calc");
    if (m == nullptr) { LOGW("%s ik: app.AnimIK2Bone.calc NOT FOUND: no recoil on the hands, no hand on the slide", TAG); return; }
    m->add_hook(pre_calc, nullptr, false);
    LOGI("%s ik: hooked app.AnimIK2Bone.calc", TAG);
}

} // namespace vn::ik
