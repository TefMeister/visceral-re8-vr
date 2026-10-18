// player.cpp -- see player.h
#include "player.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <map>
#include <set>

namespace vn::player {

namespace {
Snapshot g_now;

// praydog's get_ambiguous_re_type: the plain name, else the "FPS" twin
MO* comp(MO* go, const char* type) {
    if (auto* c = component(go, type)) return c;
    return component(go, (std::string(type) + "FPS").c_str());
}

bool type_is(MO* o, const char* full_name) {
    auto* td = o ? o->get_type_definition() : nullptr;
    for (int i = 0; td != nullptr && i < 12; ++i, td = td->get_parent_type())
        if (td->get_full_name() == full_name) return true;
    return false;
}

std::string name_of(MO* o) { return o ? read_string(call_ptr(o, "get_Name")) : ""; }

// re8_vr_recoil.lua get_weapon_recoil_id, before canonicalising: owner name, GameObject name, weaponName, type name
std::string weapon_id_raw(MO* weapon) {
    if (weapon == nullptr) return "";
    MO* owner = field_obj(weapon, "<owner>k__BackingField");
    if (owner == nullptr) owner = call_ptr(weapon, "get_owner");
    if (auto n = name_of(owner); !n.empty()) return n;
    if (auto n = name_of(call_ptr(weapon, "get_GameObject")); !n.empty()) return n;
    if (auto n = read_string(call_ptr(weapon, "get_weaponName")); !n.empty()) return n;
    return type_name(weapon);
}

MO* gun_of(MO* weapon) {
    if (weapon == nullptr) return nullptr;
    if (type_is(weapon, "app.WeaponGunCore")) return weapon;
    return component(call_ptr(weapon, "get_GameObject"), "app.WeaponGunCore");
}

} // namespace

MO* managed_string(const char* s) {   // one per name, kept alive
    static std::map<std::string, MO*> cache;
    auto it = cache.find(s);
    if (it != cache.end()) return it->second;
    std::wstring w(s, s + std::strlen(s));
    auto* m = API::get()->create_managed_string(w.c_str());
    if (m != nullptr) m->add_ref();
    return cache[s] = m;
}

namespace {
uint32_t joint_hash(const char* joint) {
    static std::map<std::string, uint32_t> cache;
    auto it = cache.find(joint);
    if (it != cache.end()) return it->second;
    auto* m = API::get()->tdb()->find_method("via.murmur_hash", "calc32");
    auto* s = managed_string(joint);
    if (m == nullptr || s == nullptr) return 0;
    auto r = m->invoke(nullptr, std::vector<void*>{(void*)s});
    if (r.exception_thrown) return 0;
    return cache[joint] = r.dword;
}
} // namespace

void refresh() {
    Snapshot s;
    auto* props = API::get()->get_managed_singleton("app.PropsManager");
    s.go = field_obj(props, "<Player>k__BackingField");
    if (s.go != nullptr) {
        s.updater = comp(s.go, "app.PlayerUpdater");
        if (s.updater == nullptr) { s.updater = comp(s.go, "app.PlayerUpdaterPl2001"); s.chris = s.updater != nullptr; }
        auto* hand_ik = field_obj(comp(s.go, "app.PlayerHandTouch"), "HandIK");
        if (call_direct<int>(hand_ik, "get_Length", 0) >= 2) {
            s.ik_right = call_ptr(hand_ik, "GetValue(System.Int32)", {(void*)(intptr_t)0});
            s.ik_left = call_ptr(hand_ik, "GetValue(System.Int32)", {(void*)(intptr_t)1});
        }
        s.motion = component(s.go, "via.motion.Motion");
        s.weapon = call_ptr(call_ptr(s.updater, "get_playerGun"), "get_equipWeaponObject");
        s.gun = gun_of(s.weapon);
        s.weapon_id = weapon_id_raw(s.weapon);
        s.tf = call_ptr(s.go, "get_Transform");
        s.weapon_tf = call_ptr(call_ptr(s.gun != nullptr ? s.gun : s.weapon, "get_GameObject"), "get_Transform");
        s.inventory = comp(s.go, "app.Inventory");
    }
    g_now = s;
}

const Snapshot& now() { return g_now; }

bool motion_joint(const char* joint, Vec3& pos, Quat& rot) {
    auto* motion = g_now.motion;
    const uint32_t hash = motion ? joint_hash(joint) : 0;
    if (hash == 0) return false;
    auto* td = motion->get_type_definition();
    auto* m_idx = find_method_deep(td, "getJointIndexByNameHash");
    auto* m_pos = find_method_deep(td, "getWorldPosition");
    auto* m_rot = find_method_deep(td, "getWorldRotation");
    if (m_idx == nullptr || m_pos == nullptr || m_rot == nullptr) return false;
    auto ri = m_idx->invoke(motion, std::vector<void*>{(void*)(uintptr_t)hash});
    const int idx = (int)ri.dword;
    if (ri.exception_thrown || idx < 0) return false;
    auto rp = m_pos->invoke(motion, std::vector<void*>{(void*)(intptr_t)idx});
    auto rr = m_rot->invoke(motion, std::vector<void*>{(void*)(intptr_t)idx});
    if (rp.exception_thrown || rr.exception_thrown) return false;
    std::memcpy(&pos, rp.bytes.data(), sizeof pos);
    std::memcpy(&rot, rr.bytes.data(), sizeof rot);
    rot = qnorm(rot);
    return std::isfinite(pos.x) && std::isfinite(rot.w);
}

bool get_pose(MO* tf, Vec3& pos, Quat& rot) {
    if (tf == nullptr || !call_vec3(tf, "get_Position", pos) || !call_quat(tf, "get_Rotation", rot)) return false;
    rot = qnorm(rot);
    return std::isfinite(pos.x) && std::isfinite(rot.w);
}

bool set_pose(MO* tf, const Vec3& pos, const Quat& rot) {
    if (tf == nullptr) return false;
    Vec3 p = pos;
    Quat q = rot;
    call_ptr(tf, "set_Position", {(void*)&p});
    call_ptr(tf, "set_Rotation", {(void*)&q});
    return true;
}

bool try_bool(MO* o, const char* method, bool& out) {
    auto* m = o ? find_method_deep(o->get_type_definition(), method) : nullptr;
    if (m == nullptr) return false;
    out = m->call<bool>(API::get()->get_vm_context(), (void*)o);
    return true;
}

// ---- ammo -------------------------------------------------------------------------------------------------------------
namespace {
// the first method of `names` the object has; logged once per (type, list) so the first start shows what answered
API::Method* first_of(MO* o, std::initializer_list<const char*> names, const char* what) {
    if (o == nullptr) return nullptr;
    static std::set<std::string> logged;
    auto* td = o->get_type_definition();
    for (const char* n : names) {
        if (auto* m = find_method_deep(td, n)) {
            const std::string key = std::string(td->get_full_name()) + what;
            if (logged.insert(key).second) LOGI("%s ammo: %s = %s.%s", TAG, what, td->get_full_name().c_str(), n);
            return m;
        }
    }
    const std::string key = std::string(td->get_full_name()) + what + "-missing";
    if (logged.insert(key).second) LOGW("%s ammo: %s NOT FOUND on %s (see type_probe.txt)", TAG, what, td->get_full_name().c_str());
    return nullptr;
}
MO* gun() { return g_now.gun; }
MO* bullet_id() {
    auto* m = first_of(gun(), {"get_bulletItemDataID", "get_bulletItemID", "getBulletItemID", "get_BulletItemID", "getBulletItemDataID"}, "bullet item id");
    if (m == nullptr) return nullptr;
    auto r = m->invoke(gun(), std::vector<void*>{});
    return r.exception_thrown ? nullptr : (MO*)r.ptr;
}
} // namespace

int loaded() {
    auto* m = first_of(gun(), {"get_loadNum", "getBulletNum", "get_LoadNum"}, "loaded");
    return m ? m->call<int>(API::get()->get_vm_context(), (void*)gun()) : -1;
}

int capacity() {
    auto* m = first_of(gun(), {"get_maxLoadNum", "get_MaxLoadNum", "getMaxBulletNum", "get_maxBulletNum", "getLoadNumMax", "get_loadNumMax"}, "capacity");
    return m ? m->call<int>(API::get()->get_vm_context(), (void*)gun()) : -1;
}

bool unlimited() {
    bool b = false;
    return try_bool(g_now.inventory, "hasUnlimitedAmmo", b) && b;
}

bool set_loaded(int n) {
    auto* m = first_of(gun(), {"set_loadNum(System.Int32)", "setLoadNum(System.Int32)", "setBulletNum(System.Int32)", "set_LoadNum(System.Int32)"}, "set loaded");
    if (m == nullptr) return false;
    m->call<void>(API::get()->get_vm_context(), (void*)gun(), (int32_t)std::max(0, n));
    return true;
}

int reserve() {
    auto* id = bullet_id();
    auto* m = first_of(g_now.inventory, {"getTotalStackNum(System.String, System.Boolean)", "getTotalStackNum(System.String)"}, "carried");
    if (id == nullptr || m == nullptr) return -1;
    if (m->get_num_params() == 1) return m->call<int>(API::get()->get_vm_context(), (void*)g_now.inventory, (void*)id);
    return m->call<int>(API::get()->get_vm_context(), (void*)g_now.inventory, (void*)id, false);
}

// RE7's safe consume (Andyalpa): findItems + setStackNum, an emptied stack gets setDelayDestroyEnabled(true)
int take_reserve(int want) {
    if (want <= 0) return 0;
    auto* id = bullet_id();
    auto* find = first_of(g_now.inventory, {"findItems(System.String, System.Boolean)"}, "find carried");
    if (id == nullptr || find == nullptr) return 0;
    auto r = find->invoke(g_now.inventory, std::vector<void*>{(void*)id, (void*)(intptr_t)0});
    auto* list = r.exception_thrown ? nullptr : (MO*)r.ptr;
    const int n = call_direct<int>(list, "get_Count", 0);
    int took = 0;
    for (int i = 0; i < n && took < want; ++i) {
        auto* item = call_ptr(list, "get_Item", {(void*)(intptr_t)i});
        const int stack = call_direct<int>(item, "getStackNum", 0);
        if (stack <= 0) continue;
        const int take = std::min(want - took, stack);
        if (auto* m = find_method_deep(item->get_type_definition(), "setStackNum(System.Int32)")) m->call<void>(API::get()->get_vm_context(), (void*)item, (int32_t)(stack - take));
        if (stack - take <= 0)
            if (auto* m = find_method_deep(item->get_type_definition(), "setDelayDestroyEnabled(System.Boolean)")) m->call<void>(API::get()->get_vm_context(), (void*)item, true);
        took += take;
    }
    return took;
}

// the game's own calls, written once the first time a gun is held: what the ammo lists above should be checked against
void probe_types() {
    static bool done = false;
    if (done || g_now.gun == nullptr) return;
    done = true;
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto dir = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8";
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    FILE* f = nullptr;
    if (_wfopen_s(&f, (dir / "type_probe.txt").c_str(), L"wb") != 0 || f == nullptr) return;
    std::set<std::string> seen;
    auto dump = [&](MO* o, const char* label) {
        std::fprintf(f, "==== %s\n", label);
        for (auto* td = o ? o->get_type_definition() : nullptr; td != nullptr; td = td->get_parent_type()) {
            const std::string tn = td->get_full_name();
            if (tn == "System.Object" || tn == "via.Component" || !seen.insert(tn).second) break;
            std::fprintf(f, "TYPE %s\n", tn.c_str());
            for (auto* m : td->get_methods()) {
                if (m == nullptr) continue;
                std::string params;
                for (auto& p : m->get_params()) {
                    if (!params.empty()) params += ", ";
                    params += p.t ? ((API::TypeDefinition*)p.t)->get_full_name() : "?";
                }
                auto* rt = m->get_return_type();
                std::fprintf(f, "  M %s(%s) -> %s\n", m->get_name(), params.c_str(), rt ? rt->get_full_name().c_str() : "void");
            }
            for (auto* fd : td->get_fields()) {
                if (fd == nullptr) continue;
                auto* ft = fd->get_type();
                std::fprintf(f, "  F %s : %s\n", fd->get_name(), ft ? ft->get_full_name().c_str() : "?");
            }
        }
    };
    dump(g_now.gun, "the gun (WeaponGunCore)");
    dump(g_now.weapon, "the weapon object");
    dump(call_ptr(g_now.updater, "get_playerGun"), "the player gun");
    dump(g_now.inventory, "the inventory");
    dump(API::get()->get_managed_singleton("app.InventoryManager"), "app.InventoryManager");
    std::fclose(f);
    LOGI("%s type_probe.txt written (the gun, the player gun and the inventory's own calls)", TAG);
}

} // namespace vn::player
