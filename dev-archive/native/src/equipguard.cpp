// equipguard.cpp -- see equipguard.h
#include "equipguard.h"
#include "common.h"
#include "weapons.h"

#include <windows.h>
#include <psapi.h>
#include <map>
#include <string>
#include <string_view>

namespace vn::equipguard {

namespace {
uintptr_t g_ref_lo = 0, g_ref_hi = 0;   // REFramework's module (DINPUT8.dll): a call returning into it came from a script
thread_local bool t_refused = false;
std::map<std::string, int> g_refused;   // object name -> how often it was refused (logged at 1, 10, 100 ...)

void find_ref_module() {
    HMODULE h = GetModuleHandleW(L"dinput8.dll");
    MODULEINFO mi{};
    if (h != nullptr && GetModuleInformation(GetCurrentProcess(), h, &mi, sizeof mi)) { g_ref_lo = (uintptr_t)mi.lpBaseOfDll; g_ref_hi = g_ref_lo + mi.SizeOfImage; }
}

bool type_is(MO* o, const char* full_name) {
    auto* td = is_managed(o) ? o->get_type_definition() : nullptr;
    for (int i = 0; td != nullptr && i < 12; ++i, td = td->get_parent_type())
        if (td->get_full_name() == full_name) return true;
    return false;
}

std::string name_of(MO* o) { return is_managed(o) ? read_string(call_ptr(o, "get_Name")) : ""; }

// the object's GameObject name (ri3042_Inventory ...), the way weapons.cpp names a gun
std::string object_name(MO* o) {
    if (!is_managed(o)) return "";
    MO* owner = field_obj(o, "<owner>k__BackingField");
    if (owner == nullptr) owner = call_ptr(o, "get_owner");
    if (auto n = name_of(owner); !n.empty()) return n;
    if (auto n = name_of(call_ptr(o, "get_GameObject")); !n.empty()) return n;
    return "";
}

// a gun the plugin knows, or a knife
bool is_weapon_we_allow(MO* o, std::string& name, std::string& why) {
    name = object_name(o);
    if (!type_is(o, "app.WeaponCore")) { why = "not an app.WeaponCore at all"; return false; }
    if (type_is(o, "app.WeaponMeleeCore")) { why = "a knife"; return true; }
    if (weapons::find(name) != nullptr) { why = "a gun the plugin knows"; return true; }
    why = "an app.WeaponCore of a kind the plugin does not know (a throwable?)";
    return false;
}

// argv[1] = this, argv[2] = the first parameter (as nodock.cpp reads them)
int pre_equip(const char* what, int argc, void** argv, unsigned long long ret_addr) {
    t_refused = false;
    if (g_ref_lo == 0 || ret_addr < g_ref_lo || ret_addr >= g_ref_hi) return REFRAMEWORK_HOOK_CALL_ORIGINAL;   // the game's own call
    if (argc < 3) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    auto* o = (MO*)argv[2];
    if (o == nullptr) return REFRAMEWORK_HOOK_CALL_ORIGINAL;   // "equip nothing": the holster clears the hand this way
    std::string name, why;
    if (is_weapon_we_allow(o, name, why)) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    t_refused = true;
    const int n = ++g_refused[name + "|" + what];
    if (n == 1 || n == 10 || n % 100 == 0)
        LOGW("%s equip guard: a script asked %s to take %s (%s): %s, REFUSED (#%d; a forced equip of such an item crashed the game twice on 2026-10-25)",
             TAG, what, name.empty() ? "an unnamed object" : name.c_str(), type_name(o).c_str(), why.c_str(), n);
    return REFRAMEWORK_HOOK_SKIP_ORIGINAL;
}
void post_equip(void** ret, REFrameworkTypeDefinitionHandle, unsigned long long) {
    if (t_refused && ret != nullptr) *ret = nullptr;   // "did not equip"
    t_refused = false;
}

int pre_wc(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long ret) { return pre_equip("app.PlayerWeaponChange.equipWeapon", argc, argv, ret); }
int pre_ec(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long ret) { return pre_equip("app.EquipController.equipWeapon", argc, argv, ret); }
int pre_set(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long ret) { return pre_equip("app.EquipController.set_equipWeaponRight", argc, argv, ret); }

int hook_all(const char* type, const char* method, int (*pre)(int, void**, REFrameworkTypeDefinitionHandle*, unsigned long long)) {
    auto* td = API::get()->tdb()->find_type(type);
    if (td == nullptr) { LOGW("%s equip guard: %s NOT FOUND", TAG, type); return 0; }
    int n = 0;
    for (auto* m : td->get_methods()) {   // every overload with a first parameter (the holster uses equipWeapon(app.WeaponCore) and (WeaponCore, bool))
        if (std::string_view(m->get_name()) != method || m->get_num_params() < 1) continue;
        m->add_hook(pre, post_equip, false);
        ++n;
    }
    LOGI("%s equip guard: %s.%s hooked (%d overload(s))", TAG, type, method, n);
    return n;
}
} // namespace

void install() {
    find_ref_module();
    if (g_ref_lo == 0) { LOGW("%s equip guard: REFramework's module not found: the guard stays off", TAG); return; }
    hook_all("app.PlayerWeaponChange", "equipWeapon", pre_wc);
    hook_all("app.EquipController", "equipWeapon", pre_ec);
    hook_all("app.EquipController", "set_equipWeaponRight", pre_set);
}

} // namespace vn::equipguard
