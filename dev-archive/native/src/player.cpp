// player.cpp -- see player.h
#include "player.h"

#include <cstring>
#include <map>

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

MO* managed_string(const char* s) {   // one per name, kept alive
    static std::map<std::string, MO*> cache;
    auto it = cache.find(s);
    if (it != cache.end()) return it->second;
    std::wstring w(s, s + std::strlen(s));
    auto* m = API::get()->create_managed_string(w.c_str());
    if (m != nullptr) m->add_ref();
    return cache[s] = m;
}

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

} // namespace vn::player
