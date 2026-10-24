// reload_internal.h -- shared by reload.cpp (the state machine, which owns the state) and reload_pose.cpp (where the
// magazine and the shell are drawn), split apart on 2026-10-24 (the 800-line rule). Not for any other file.
#pragma once
#include "reload.h"
#include "weapons.h"

#include <string>

namespace vn::reload::detail {

enum class St { SEATED, SLIDE_OUT, FALL, OUT, IN_HAND, HAND_FALL, INSERT };

// ---- the state (defined in reload.cpp) ------------------------------------------------------------------------------
extern St g_st;
extern const weapons::Weapon* g_w;
extern std::string g_id;
extern MO* g_gun;
extern MO* g_wtf;
extern MO* g_joint;
extern MO* g_joint2;
extern MO* g_hand;
extern float g_t0;
extern Vec3 g_rest_pos, g_rest_scale;
extern Quat g_rest_rot;
extern Vec3 g_fall_from;
extern Quat g_fall_rot;
extern bool g_scale_restore;
extern bool g_round_in_hand;
extern MO* g_shell;
extern Vec3 g_shell_rest;
extern Quat g_shell_rest_rot;
extern bool g_shell_have_rest;

// ---- the pose helpers reload.cpp calls (defined in reload_pose.cpp) -------------------------------------------------
Vec3 mag_out_pos();
Quat quat_from_ypr(float yaw, float pitch, float roll);
bool from_weapon_local(Vec3 lpos, Quat lrot, Vec3& world, Quat& wrot);
bool held_pose(Vec3& pos, Quat& rot);
void magazine_shown(bool show);
void mag_part_shown(bool show);
void hide_mag_part();
void write_scale(Vec3 s);
void capture_second();
void pose_shell();
void shell_home();
void log_parts();
void pose_joint();
void log_joints();

} // namespace vn::reload::detail
