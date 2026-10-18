// player.h -- the player objects the ported features need, found the way praydog's RE8VR.cpp finds them
// (REFramework src/mods/vr/games/RE8VR.cpp: get_localplayer, update_pointers, update_ik_pointers, get_weapon_object),
// so they are the same objects re8_vr.lua's `re8vr` table holds (re8vr.right_hand_ik, re8vr.weapon ...). 2026-10-15.
// Refreshed once per frame (UpdateBehavior pre); the hooks that run later in the frame read the snapshot.
#pragma once
#include "common.h"

#include <string>

namespace vn::player {

struct Snapshot {
    MO* go = nullptr;          // app.PropsManager.<Player>k__BackingField (a via.GameObject)
    MO* updater = nullptr;     // app.PlayerUpdater, or app.PlayerUpdaterPl2001 (Chris, Mercenaries)
    bool chris = false;
    MO* ik_right = nullptr;    // app.PlayerHandTouch.HandIK[0] / [1] (app.AnimIK2Bone)
    MO* ik_left = nullptr;
    MO* motion = nullptr;      // the player's via.motion.Motion
    MO* weapon = nullptr;      // PlayerGun.get_equipWeaponObject (re8vr.weapon)
    MO* gun = nullptr;         // the weapon's app.WeaponGunCore (the weapon itself, or a component of its GameObject)
    std::string weapon_id;     // the recoil id: the owner's / GameObject's name, canonicalised by the caller's catalog
    // added 2026-10-18 for reload.cpp / rack.cpp
    MO* tf = nullptr;          // the player's via.Transform
    MO* weapon_tf = nullptr;   // the weapon GameObject's via.Transform
    MO* inventory = nullptr;   // app.Inventory on the player
};

void refresh();                    // once per frame, game thread
const Snapshot& now();
// world pose of a joint of the player's animation (via.motion.Motion), e.g. "l_arm_wrist"; false when not readable
bool motion_joint(const char* joint, Vec3& pos, Quat& rot);
// read / write a via.Transform's world pose (the IK target)
bool get_pose(MO* transform, Vec3& pos, Quat& rot);
bool set_pose(MO* transform, const Vec3& pos, const Quat& rot);
// a bool getter on an object: true when the method exists (its answer goes to `out`)
bool try_bool(MO* o, const char* method, bool& out);
MO* managed_string(const char* s);   // one per text, kept alive
// the overload of `name` with `nparams` parameters, searched up the type chain (a bare name can land on any overload)
API::Method* overload(MO* o, const char* name, uint32_t nparams);

// ammo of the gun in hand (2026-10-18), Village's own model (player.cpp). -1 / false = unknown.
int loaded();                      // the rounds in the gun (its item record's include stack)
int capacity();
int reserve();                     // rounds of this gun's ammo carried
bool unlimited();
bool set_loaded(int n);            // false when the gun has no item record
int game_reload(int n);            // the game's own reload maths: n < 0 = fill up, else up to n; returns rounds added
void probe_types();                // once, first game frame: the ammo types' calls to type_probe.txt

} // namespace vn::player
