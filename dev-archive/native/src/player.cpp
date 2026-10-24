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
    auto* td = is_managed(o) ? o->get_type_definition() : nullptr;
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

API::Method* overload(MO* o, const char* name, uint32_t nparams) {
    for (auto* td = is_managed(o) ? o->get_type_definition() : nullptr; td != nullptr; td = td->get_parent_type())   // null or stale: nothing
        for (auto* m : td->get_methods())
            if (m != nullptr && m->get_num_params() == nparams && std::strcmp(m->get_name(), name) == 0) return m;
    return nullptr;
}

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
        // Village: a gun is an item (app.ItemCore), not a component: its GameObject is its owner (Agent.get_owner), and the
        // player's inventory is InventoryManager.get_activeInventory (headset run 2026-10-18: both read "NOT FOUND" before)
        MO* wgo = s.gun != nullptr ? call_ptr(s.gun, "get_owner") : nullptr;
        if (wgo == nullptr) wgo = field_obj(s.gun, "<owner>k__BackingField");
        if (wgo == nullptr) wgo = call_ptr(s.weapon, "get_GameObject");
        s.weapon_tf = call_ptr(wgo, "get_Transform");
        s.inventory = call_ptr(API::get()->get_managed_singleton("app.InventoryManager"), "get_activeInventory");
        if (s.inventory == nullptr) s.inventory = comp(s.go, "app.Inventory");
    }
    g_now = s;
}

const Snapshot& now() { return g_now; }

bool motion_joint(const char* joint, Vec3& pos, Quat& rot) {
    auto* motion = g_now.motion;
    const uint32_t hash = is_managed(motion) ? joint_hash(joint) : 0;
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
    auto* m = is_managed(o) ? find_method_deep(o->get_type_definition(), method) : nullptr;
    if (m == nullptr) return false;
    out = m->call<bool>(API::get()->get_vm_context(), (void*)o);
    return true;
}

// ---- ammo (Village's own model, read from the game's type database 2026-10-18, type_probe.txt) ----------------------
// A gun is an item (app.ItemCore); its record (get_work: app.ItemCore.InstanceWork) holds the loaded rounds as an
// "include" stack: includeStackSize for the normal ammo, includeStackSizeSub for the second kind (usingBulletIndex 1).
// The carried ammo is counted by Inventory.getTotalStackSize(bullet item id, ...), and the gun's own
// WeaponGunCore.reload() / reload(int) move carried rounds into it the game's way (the animation is PlayerGun.tryReload,
// which reload.cpp skips for our guns). [hypothesis] for the reload calls' exact behaviour until the first headset run:
// every use logs the rounds before and after.
namespace {
MO* gun() { return g_now.gun; }
MO* work() { return call_ptr(gun(), "get_work"); }
bool sub() { return call_direct<int>(gun(), "get_usingBulletIndex", 0) == 1; }
API::Method* m_of(MO* o, const char* name) { return is_managed(o) ? find_method_deep(o->get_type_definition(), name) : nullptr; }
} // namespace

int loaded() {
    auto* w = work();
    if (w != nullptr) return call_direct<int>(w, sub() ? "get_includeStackSizeSub" : "get_includeStackSize", -1);
    return call_direct<int>(gun(), "getBulletNum", -1);
}

int capacity() {
    const int n = call_direct<int>(work(), "getMaxIncludeStackSize", -1);
    return n >= 0 ? n : call_direct<int>(gun(), "getMaxIncludeStackSize", -1);
}

bool unlimited() {
    bool b = false;
    return try_bool(gun(), "get_isLoadNumInfinity", b) && b;
}

bool set_loaded(int n) {
    auto* w = work();
    auto* m = m_of(w, sub() ? "set_includeStackSizeSub(System.Int32)" : "set_includeStackSize(System.Int32)");
    if (m == nullptr) { LOGW("%s ammo: no item record on the gun: cannot set its rounds", TAG); return false; }
    m->call<void>(API::get()->get_vm_context(), (void*)w, (int32_t)std::max(0, n));
    return true;
}

// the bullet item of the ammo in use. 2026-10-18 headset run: "getBulletItemID" by bare name found the (int) overload and
// read 0, so every gun said "carried -1"; now the exact signature, then the item record's includeItemID(Sub)
uint32_t bullet_item_id() {
    uint32_t id = 0;
    auto* m = overload(gun(), "getBulletItemID", 0);
    if (m != nullptr) id = m->call<uint32_t>(API::get()->get_vm_context(), (void*)gun());
    const uint32_t from_work = call_direct<uint32_t>(work(), sub() ? "get_includeItemIDSub" : "get_includeItemID", 0u);
    static MO* logged = nullptr;
    if (logged != gun()) {
        logged = gun();
        LOGI("%s ammo: bullet item id: getBulletItemID() %s -> %u, item record %s -> %u", TAG, m ? "found" : "NOT FOUND", id,
             work() ? "found" : "NOT FOUND", from_work);
    }
    return id != 0 ? id : from_work;
}

int reserve() {
    const uint32_t id = bullet_item_id();
    auto* m = overload(g_now.inventory, "getTotalStackSize", 3);
    static bool told = false;
    if ((id == 0 || m == nullptr) && !told) { told = true; LOGW("%s ammo: carried unknown: item id %u, inventory %s, getTotalStackSize %s", TAG, id, g_now.inventory ? "found" : "NOT FOUND", m ? "found" : "NOT FOUND"); }
    if (id == 0 || m == nullptr) return -1;
    auto* ctx = API::get()->get_vm_context();
    static uint32_t logged = 0;
    if (logged != id) {   // the two bools are not named in the type list: log all four answers once per ammo kind
        logged = id;
        LOGI("%s ammo: carried of item %u = %d / %d / %d / %d (bools ff / tf / ft / tt)", TAG, id,
             m->call<int>(ctx, (void*)g_now.inventory, id, false, false), m->call<int>(ctx, (void*)g_now.inventory, id, true, false),
             m->call<int>(ctx, (void*)g_now.inventory, id, false, true), m->call<int>(ctx, (void*)g_now.inventory, id, true, true));
    }
    return m->call<int>(ctx, (void*)g_now.inventory, id, false, false);
}

// the game's own reload maths: n < 0 = fill up (reload()), else up to n rounds (reload(int)); returns rounds added
int game_reload(int n) {
    const int before = loaded();
    auto* m = overload(gun(), "reload", n < 0 ? 0 : 1);
    if (m == nullptr) { LOGW("%s ammo: WeaponGunCore.%s not found", TAG, n < 0 ? "reload()" : "reload(int)"); return 0; }
    if (n < 0) m->call<void>(API::get()->get_vm_context(), (void*)gun());
    else m->call<void>(API::get()->get_vm_context(), (void*)gun(), (int32_t)n);
    const int after = loaded();
    LOGI("%s ammo: the game's %s: loaded %d -> %d, carried now %d", TAG, n < 0 ? "reload()" : "reload(n)", before, after, reserve());
    return after - before;
}

// the game's own calls, written once at the first game frame (the title screen is enough): every method and field of the
// types the ammo code needs, read from the type database, plus the names of all app.* types about reloads and bullets.
// What the ammo lists above should be checked against.
void probe_types() {
    static bool done = false;
    if (done) return;
    done = true;
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto dir = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8";
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    FILE* f = nullptr;
    if (_wfopen_s(&f, (dir / "type_probe.txt").c_str(), L"wb") != 0 || f == nullptr) return;
    std::set<std::string> seen;
    auto dump_type = [&](API::TypeDefinition* td) {
        for (; td != nullptr; td = td->get_parent_type()) {
            const std::string tn = td->get_full_name();
            if (tn == "System.Object" || tn == "via.Component" || tn == "via.Behavior" || !seen.insert(tn).second) break;
            std::fprintf(f, "TYPE %s\n", tn.c_str());
            for (auto* m : td->get_methods()) {
                if (m == nullptr) continue;
                std::string params;
                for (auto& prm : m->get_params()) {
                    if (!params.empty()) params += ", ";
                    params += prm.t ? ((API::TypeDefinition*)prm.t)->get_full_name() : "?";
                }
                auto* rt = m->get_return_type();
                std::fprintf(f, "  M %s(%s) -> %s\n", m->get_name(), params.c_str(), rt ? rt->get_full_name().c_str() : "void");
            }
            for (auto* fd : td->get_fields()) {
                if (fd == nullptr) continue;
                auto* ft = fd->get_type();
                std::fprintf(f, "  F %s%s : %s\n", fd->is_static() ? "static " : "", fd->get_name(), ft ? ft->get_full_name().c_str() : "?");
            }
        }
    };
    auto* tdb = API::get()->tdb();
    for (const char* t : {"app.WeaponGunCore", "app.WeaponGun", "app.PlayerGun", "app.PlayerGunFPS", "app.Inventory", "app.InventoryManager",
                          "app.ItemCore", "app.ItemSlotManager", "app.PlayerStatus", "app.PlayerStatusFPS", "app.PlayerReloadController",
                          "app.ItemCore.InstanceWork", "via.Transform", "via.Joint", "via.render.Mesh", "app.GUIRemainAmmo"}) {
        auto* td = tdb->find_type(t);
        std::fprintf(f, "==== %s%s\n", t, td ? "" : " (not in this game)");
        if (td) dump_type(td);
    }
    // the item record's own parts, one level down (where a gun keeps its loaded rounds)
    if (auto* iw = tdb->find_type("app.ItemCore.InstanceWork")) {
        for (auto* fd : iw->get_fields()) {
            auto* ft = fd ? fd->get_type() : nullptr;
            if (ft == nullptr || ft->get_full_name().rfind("app.", 0) != 0) continue;
            std::fprintf(f, "==== field %s of the item record\n", fd->get_name());
            dump_type(ft);
        }
    }
    std::fprintf(f, "==== app.* types with Reload / Bullet / Ammo / Magazine in the name\n");
    std::vector<API::TypeDefinition*> extra;
    const uint32_t n = tdb->get_num_types();
    for (uint32_t i = 0; i < n; ++i) {
        auto* td = tdb->get_type(i);
        if (td == nullptr) continue;
        const std::string tn = td->get_full_name();
        if (tn.rfind("app.", 0) != 0) continue;
        if (tn.find("Reload") != std::string::npos || tn.find("Bullet") != std::string::npos || tn.find("Ammo") != std::string::npos ||
            tn.find("Magazine") != std::string::npos) {
            std::fprintf(f, "NAME %s\n", tn.c_str());
            if (tn.find("Reload") != std::string::npos) extra.push_back(td);
        }
    }
    for (auto* td : extra) dump_type(td);
    std::fclose(f);
    LOGI("%s type_probe.txt written (the ammo types' own calls, from the type database)", TAG);
}

} // namespace vn::player
