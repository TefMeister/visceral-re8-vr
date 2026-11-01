// pumpbolt.cpp -- see pumpbolt.h
#include "pumpbolt.h"
#include "joints.h"
#include "player.h"
#include "settings.h"
#include "weapons.h"

#include <string>

namespace vn::pumpbolt {

using namespace joints;
using namespace vn::settings;

namespace {
struct Follow { const char* gun; const wchar_t* pump; const wchar_t* part; };
// the part that moves with each pump gun's handle (the W870's ejection port has no moving joint in its model)
const Follow FOLLOW[] = { {"ri3036_Inventory", L"Reload_Slider", L"Bolt"}, {"ri3084_Inventory", L"Reload_Slider", L"Bolt"},
                          {"ri3147_Inventory", L"Reload_Slider", L"Bolt"} };
std::string g_gun;
MO* g_pump = nullptr;
MO* g_part = nullptr;
Vec3 g_pump_rest{}, g_part_rest{};
bool g_ok = false;
int g_frames = 0;
} // namespace

void point() {
    if (!PUMP_BOLT_ON) return;
    const auto& s = player::now();
    const std::string id = weapons::canonical(s.weapon_id);
    if (id != g_gun) {
        g_gun = id; g_pump = g_part = nullptr; g_ok = false; g_frames = 0;
        for (const auto& f : FOLLOW)
            if (id == f.gun && s.weapon_tf != nullptr) { g_pump = joint_by_name(s.weapon_tf, f.pump); g_part = joint_by_name(s.weapon_tf, f.part); }
    }
    if (g_pump == nullptr || g_part == nullptr) return;
    if (!g_ok) {   // the rests, taken once the draw has settled (both joints shut)
        if (++g_frames < PUMP_BOLT_SETTLE_FRAMES) return;
        g_ok = get_v3(JOINT, g_pump, "get_LocalPosition", g_pump_rest) && get_v3(JOINT, g_part, "get_LocalPosition", g_part_rest);
        LOGI("%s pumpbolt: %s: the bolt follows the pump (rests: pump z %.3f, bolt z %.3f)", TAG, g_gun.c_str(), g_pump_rest.z, g_part_rest.z);
        if (!g_ok) { g_pump = nullptr; return; }
    }
    Vec3 p;
    if (!get_v3(JOINT, g_pump, "get_LocalPosition", p)) return;
    Vec3 b{g_part_rest.x + (p.x - g_pump_rest.x), g_part_rest.y + (p.y - g_pump_rest.y), g_part_rest.z + (p.z - g_pump_rest.z)};
    set_any(JOINT, g_part, "set_LocalPosition", &b);
}

} // namespace vn::pumpbolt
