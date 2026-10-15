// recoil_test.cpp -- runs the SHIPPED src/recoil.cpp (included whole, VN_RECOIL_TEST swaps only its clock and random
// source) through fixed shot sequences and prints the hand offset every frame. recoil_test.lua runs Andyalpa's
// original re8_vr_recoil.lua through the same sequences; compare.py checks the two agree. No game, no REFramework:
// the bridge, the player lookup and the managed-call helpers are stubbed below. 2026-10-15.
#define VN_RECOIL_TEST
#include "../../src/recoil.cpp"

#include <cstdio>
#include <cstring>
#include <string>

static double g_clock = 0.0;
namespace vn::recoil { namespace {   // the same (anonymous) namespace recoil.cpp declared them in
double vn_test_clock() { return g_clock; }
float vn_test_random() { return 0.5f; }   // randomness and spreads cancel at 0.5 (both sides)
} }

// ---- stubs ---------------------------------------------------------------------------------------------------------
static bool g_lgrip = false;
static vn::player::Snapshot g_snap;
namespace vn {
const REFrameworkPluginInitializeParam* g_param = nullptr;
bool is_managed(void*) { return false; }
std::string type_name(MO*) { return "test"; }
API::Method* find_method_deep(API::TypeDefinition*, std::string_view) { return nullptr; }
API::Field* find_field_deep(API::TypeDefinition*, std::string_view) { return nullptr; }
MO* field_obj(MO*, std::string_view) { return nullptr; }
std::string read_string(void*) { return ""; }
MO* call_ptr(MO*, std::string_view, std::vector<void*>) { return nullptr; }
bool call_vec3(MO*, std::string_view, Vec3&) { return false; }
bool call_quat(MO*, std::string_view, Quat&) { return false; }
MO* component(MO*, const char*) { return nullptr; }
namespace bridge {
bool live() { return true; }
bool held(Slot s) { return s == S_LGRIP && g_lgrip; }
float view(Slot s) { return s == S_RECOIL_FLAGS ? 0.0f : NO_VALUE; }
Vec3 view_vec3(Slot) { return {NO_VALUE, 0, 0}; }
bool flag(Slot s) { return s == S_CAN_USE_HANDS; }
} // namespace bridge
namespace player {
const Snapshot& now() { return g_snap; }
bool try_bool(MO*, const char*, bool&) { return false; }
bool motion_joint(const char*, Vec3&, Quat&) { return false; }
bool get_pose(MO*, Vec3&, Quat&) { return false; }
bool set_pose(MO*, const Vec3&, const Quat&) { return false; }
} // namespace player
} // namespace vn

using namespace vn::recoil;

// one scenario: weapon id, two hands?, the frames a shot lands on, frame count, frame step
static void run(const char* name, const char* weapon_id, bool two, const int* shots, int n_shots, int frames, float dt) {
    g_snap = vn::player::Snapshot{};
    g_snap.weapon = (vn::MO*)0x1000;   // never dereferenced: the catalogued ids need no game calls
    g_snap.weapon_id = weapon_id;
    g_lgrip = two;
    g_cfg = Cfg{};
    g_cfg.randomness = 0.0f;
    cancel_state();               // as the Lua's cancel_recoil_state: the last shot's time is kept, so the clock
    m_eq = Equipped{};            // keeps running between scenarios (+10 s), the same on both sides
    g_clock += 10.0;
    for (int f = 0; f < frames; ++f) {
        g_frame.store(g_frame.load() + 1);
        for (int i = 0; i < n_shots; ++i)
            if (shots[i] == f) kick(g_snap.weapon, canonical(weapon_id));
        update_spring(dt);
        float p, y, a, b;
        effective(p, y, a, b);
        std::printf("%s,%d,%.9g,%.9g,%.9g,%.9g,%d\n", name, f, p, y, a, b, m_fade.active ? 1 : 0);
        g_clock += (double)dt;
    }
}

// the saved file Andyalpa shipped, through the same reader recoil.cpp uses
static void cfg_check(const char* path) {
    std::wstring w(path, path + std::strlen(path));
    vn::json::Value v;
    const bool ok = vn::json::load_file(w, v);
    const auto* weapons = v.get("weapons");
    const auto* m1911 = weapons ? weapons->get("ri3040_Inventory") : nullptr;
    const auto* in = m1911 ? m1911->get("intensity") : nullptr;
    std::fprintf(stderr, "cfg %s: parsed %d, %d keys, %d weapons, intensity %.3f, M1911 %.3f\n", path, (int)ok,
                 (int)v.obj.size(), weapons ? (int)weapons->obj.size() : -1, v.get("intensity") ? v.get("intensity")->n : -1.0,
                 in ? in->n : -1.0);
}

int main(int argc, char** argv) {
    if (argc > 1) cfg_check(argv[1]);
    const int one[] = {0};
    const int burst[] = {0, 6, 12, 18};
    run("handgun_one_hand", "ri3040_Inventory", false, one, 1, 120, 1.0f / 90.0f);
    run("shotgun_two_hands", "ri3021_Inventory", true, one, 1, 120, 1.0f / 90.0f);
    run("auto_rifle_burst", "ri3049_Inventory", true, burst, 4, 150, 1.0f / 90.0f);
    run("magnum_one_hand_60hz", "ri3008", false, one, 1, 90, 1.0f / 60.0f);   // id without _Inventory: canonicalised
    return 0;
}
