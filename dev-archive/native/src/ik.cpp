// ik.cpp -- see ik.h
#include "ik.h"
#include "common.h"
#include "player.h"
#include "rack.h"
#include "recoil.h"
#include "reload.h"

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
