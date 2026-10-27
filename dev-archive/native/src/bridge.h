// bridge.h -- controller readings in, rumble out, through lua/visceral_re8_bridge.lua's shared float array.
// Same idea as visceral-re2-vr's bridge (REFramework API 1.15 gives C++ no VR buttons and no rumble), with one
// Village difference: the VR layer here is praydog's re8_vr.lua (the `re8vr` table), not REFramework's C++, so the
// bridge also carries the few re8vr readings and Hands Off globals that the C++ ports need while the rest of the
// pack still runs as Lua. Each slot below says which Lua file it stands in for; when that file is ported, the slot
// is filled by the plugin instead and the Lua line goes.
#pragma once
#include "common.h"

namespace vn::bridge {

enum Slot : int {
    S_FRAME = 0,
    S_HMD = 1,            // 1 = headset active AND controllers in use (vrmod:is_hmd_active() and is_using_controllers())
    S_LGRIP = 2, S_LTRIG = 3, S_RGRIP = 4, S_RTRIG = 5,    // digital actions (vrmod:is_action_active)
    S_LA = 6, S_LB = 7, S_RA = 8, S_RB = 9,
    S_RUMBLE_L_AMP = 10, S_RUMBLE_L_SEC = 11, S_RUMBLE_L_HZ = 12,   // written by the plugin, fired + cleared by the Lua
    S_RUMBLE_R_AMP = 13, S_RUMBLE_R_SEC = 14, S_RUMBLE_R_HZ = 15,
    S_HMD_POS = 16, S_HMD_ROT = 19, S_LPOS = 23, S_RPOS = 26,       // VR tracking space (the real room)
    S_ACK = 30, S_SENTINEL = 31,
    // grip axes, -1 when vrmod has none (re8_vr_haptics.lua read_grip_axis)
    S_LGRIP_AXIS = 32, S_RGRIP_AXIS = 33,
    // 1 = some other left-grip signal is on: the holster's own left grip, re8vr.is_holding_left_grip, or the
    // VRControllerManager GRIP action on the left controller (re8_vr_haptics.lua read_left_grip, its last three tests)
    S_LGRIP_OTHER = 34,
    S_RE8VR = 35,         // 1 = praydog's re8vr table exists
    S_GRIPPING_WEAPON = 36,   // re8vr.was_gripping_weapon (the left hand is docked on the gun)
    S_HANDS_W_OK = 37,    // 1 = the two slots below hold re8vr.last_left/right_hand_position (game world, metres)
    S_LHAND_W = 38, S_RHAND_W = 41,
    S_WEAPON_AUTO = 44,   // re8vr.weapon:call("enableFullAuto")
    // Hands Off globals still published by Lua files not yet ported (re8_vr_holster.lua)
    S_IN_HOLSTER_ZONE = 45,       // __vr_in_holster_zone
    S_IN_FLASHLIGHT_ZONE = 46,    // __vr_in_head_flashlight_zone
    S_MASTER_OFF = 47,            // __vr_reloaded_master_enabled == false
    // haptics settings, from lua/visceral_re8_menu.lua (Andyalpa's re8_vr/re8_vr_haptics.json, same file and keys)
    S_HAP_SENT = 48,      // 1 = the menu has sent the numbers below
    S_HAP_ON = 49, S_HAP_GATE_LEFT = 50, S_HAP_SCALE = 51, S_HAP_AUTO_PULSE = 52,
    S_HAP_ON_S = 53, S_HAP_OFF_S = 54, S_HAP_MAX_DUR = 55,
    // WRITTEN BY THE PLUGIN: 1 = haptics.cpp forwards the game's rumble, so re8_vr.lua's own two forwards stand down
    S_NATIVE_HAPTICS = 56,
    // recoil.cpp (re8_vr_recoil.lua): three re8vr readings and the other mods' globals the Lua checked
    S_CAN_USE_HANDS = 57,     // re8vr.can_use_hands ~= false (praydog: no cutscene, no vehicle ...)
    S_IS_RELOADING = 58,      // re8vr.is_reloading
    S_AIMING = 59,            // player_is_aiming(): re8vr.order's playerGun aim states, or playerCamera.isGunAim
    S_RECOIL_FLAGS = 60,      // bits, see RecoilFlag (all 0 with the Hands Off pack alone: no file of it sets them)
    // reload.cpp / rack.cpp (2026-10-18, moved over from the RE7 RELOADED mod)
    S_LROT = 64, S_RROT = 68,                         // controller rotations, room space (x,y,z,w)
    S_CAM_POS = 72, S_CAM_ROT = 75,                   // the game camera's world pose (rotation x,y,z,w)
    S_IN_AMMO_ZONE = 79,      // __vr_in_ammo_holster_zone: the left hand in Andyalpa's left-hip ammo spot (re8_vr_holster.lua)
    S_CUTSCENE = 80,          // re8vr.is_in_cutscene
    S_RELOAD_BUSY = 81,       // WRITTEN BY THE PLUGIN: 1 = a reload / rack in the left hand (our re8_vr.lua then skips the block pose)
    S_HAND_STATE = 82,        // WRITTEN BY THE PLUGIN: handstate.h code of the left hand, for the menu
    S_POSE_LOCK = 83,         // WRITTEN BY THE LUA MENU: 1 = "hold this pose"
    S_SLIDE_HAND_X = 84, S_SLIDE_HAND_Y = 85, S_SLIDE_HAND_Z = 86,
    S_HUD_PING = 87,          // WRITTEN BY THE PLUGIN: +1 whenever our reload changed the ammo; the Lua refreshes the ammo display   // WRITTEN BY THE LUA MENU: the hand on the slide, nudged (cm, gun axes)
    // ammo_hud.cpp (re8_vr_ammo_hud.lua, 2026-10-19)
    S_BARE_HANDS = 88,        // __re8_bare_hands (the holster: nothing in the right hand)
    S_INTERACTION_BLOCKED = 89,   // __vr_is_interaction_blocked() (the holster: a menu / inventory is up)
    S_HUD_CMD = 90, S_HUD_CMD_SEQ = 91,   // WRITTEN BY THE LUA MENU: a button (1 open now, 2 recover, 3 re-resolve), numbered
    S_HUD_STATUS = 92,        // WRITTEN BY THE PLUGIN: ammo_hud.cpp's status, for the menu
    // 2026-10-24 (Tefa: "using LG + LT to rack makes no gun sounds"): sound requests to lua/visceral_re8_sounds.lua
    S_SFX_CODE = 61, S_SFX_SEQ = 62,   // WRITTEN BY THE PLUGIN: which handling sound (Sfx below), numbered so a repeat plays again
    S_SFX_LUA_HAS = 63,       // WRITTEN BY THE LUA: bit (1 << code) = the Lua has a game sound for that code (else the plugin's wav, if any)
    S_SLIDE_HAND_ROT = 93,    // 93-95, WRITTEN BY THE LUA MENU: the hand on the slide / pump / bolt turned (deg, about the gun's x, y, z)
    S_EXPERIMENT = 96,        // WRITTEN BY THE LUA MENU: Experiment bits, for trying a fix live without a rebuild
    S_WEAPON_NUM = 97,        // WRITTEN BY THE PLUGIN: the held gun's number (ri3046 -> 3046), 0 = none (the menu keeps settings per gun)
    S_GRIP_VETO = 98,         // WRITTEN BY THE PLUGIN: 1 = the left hand is ours (on the magazine): the scope's grip script must not take it
    // 2026-10-25 (Tefa: "cannot two hand a gun, even when LG is held"): on a pump gun the two-handed grip IS the pump, which
    // rack.cpp holds; the grip script steers the gun at the rack's socket while this says so
    S_POSER_HELD = 29,        // WRITTEN BY THE LUA: joints a hand poser (hand_poser.lua) holds right now; fingers.cpp stands down
    S_RACK_TWOHAND = 99,      // WRITTEN BY THE PLUGIN: 1 = the left hand is on a pump: the grip script steers at S_RACK_SOCKET
    S_RACK_SOCKET = 100,      // 100-102, WRITTEN BY THE PLUGIN: where the rack draws the left hand, in the right hand's frame (m)
    S_DOCK_ALLOW = 105,       // WRITTEN BY THE GRIP SCRIPT: 1 = let the game dock the left hand now (a pistol's first grip spot is learned from it)
    S_LONG_GUN = 104,         // WRITTEN BY THE PLUGIN: 1 = the gun in hand is a long gun (the grip script allows no grip near the right hand)
    S_BODY_TURN = 103,        // WRITTEN BY THE LUA MENU: 1 = the body turn (body.cpp, experimental) is on
    S_LHAND_OFF = 106,        // 106-108, WRITTEN BY THE LUA: praydog's re8vr.left_hand_position_offset (the hand 15 cm ahead of the controller)
    S_LHAND_ROT_OFF = 109,    // 109-112, WRITTEN BY THE LUA: re8vr.left_hand_rotation_offset (x,y,z,w)
    S_ZONE_SHOW = 114,        // WRITTEN BY THE LUA MENU: 1 = draw the grab zones on the gun (lua/visceral_re8_zones.lua)
    S_ZONE_SEQ = 115,         // WRITTEN BY THE LUA MENU: +1 whenever zones.json was saved (zones.cpp re-reads it)
    S_ZONES = 116,            // 116-140, WRITTEN BY THE PLUGIN: five zones x {x, y, z (world, m), radius (m), on}: the magazine grab,
                              // the well (where it goes in), the slide / pump / bolt (on = 1 slide, 2 pump, 3 bolt), the hand point tested
    S_ARC_CM = 141,           // WRITTEN BY THE LUA BRIDGE: how high (cm) the left hand arcs over the gun on its way onto / off the slide / pump / bolt (2026-10-25)
    S_PAIR_ACT = 142,         // 142-146, WRITTEN BY THE PLUGIN: the shown hand pair's ACTIVATION sphere {x, y, z (world, m), radius, on} (pairs.h)
    S_PAIR_LAND = 147,        // 147-151, WRITTEN BY THE PLUGIN: the shown pair's LANDING spot {x, y, z, dot radius, on}
    S_PAIR_ACTIVE = 152,      // WRITTEN BY THE PLUGIN: the number of the pair holding the left hand now, 0 = none
    S_LEFT_SPOT = 153,        // WRITTEN BY THE PLUGIN: where the left hand is, for Hand Poser's pose per spot (pairs.cpp):
                              // 1000+N on pair N's landing spot, 2000+N inside pair N's activation sphere, 3 slide/pump/bolt, 4 magazine, 0 none
    S_ZONES2 = 154,           // 154-168, WRITTEN BY THE PLUGIN: three more zones x {x, y, z, r, on}: the HANDLE, the DRUM, the INSERT
                              // point (zones.h, 2026-10-27); the left hand's spot (153) gains 5 handle, 6 drum, 7 insert;
                              // 2026-10-28: 8 a pistol's slide taken from the gun hand's left (3 stays the right side)
    S_COUNT = 169,            // 2026-10-27: 154-168 the handle / drum / insert zones; 2026-10-26: 153 the left hand's spot; 2026-10-25: 142-152 the hand pairs; 136-140 the FRONT GRIP zone
};
enum Sfx : int {               // S_SFX_CODE values
    SFX_SLIDE_BACK = 1, SFX_SLIDE_FORWARD = 2, SFX_PUMP_BACK = 3, SFX_PUMP_FORWARD = 4,
    SFX_BOLT_UP = 5, SFX_BOLT_BACK = 6, SFX_BOLT_FORWARD = 7, SFX_BOLT_DOWN = 8,
    SFX_MAG_OUT = 9, SFX_MAG_IN = 10, SFX_SHELL_IN = 11,   // 2026-10-24 (Tefa: "not the mag being inserted")
};
enum Experiment : int {        // S_EXPERIMENT bits (menu "Visceral RE8 reload" -> "Experiments")
    EX_MAG_HIDE_AT_DROP = 1,   // the old way: the gun's own magazine display switched off the moment the magazine drops
    EX_MAG_NO_SECOND = 2,      // do NOT move "Magazine_second" with "Magazine"
    EX_NO_SMOOTH = 4,          // no smoothing of the left hand going onto / off the gun
    EX_GAME_RELOAD = 8,        // the game's own reload is let through (its motion plays the gun's handling sounds, learned by the Lua)
};
void sfx(Sfx code);            // ask the Lua for a handling sound (plays the plugin's wav itself when the Lua has none)
bool experiment(Experiment e);

enum RecoilFlag : int {       // S_RECOIL_FLAGS bits = the globals re8_vr_recoil.lua read
    RF_BLOCK_LEFT_IK = 1,     // __vr_block_left_hand_ik
    RF_BLOCK_FIRE_EMPTY = 2,  // __vr_block_fire_when_empty
    RF_MANUAL_RELOAD = 4,     // __vr_manual_reload_enabled
    RF_MAG_DROPPED = 8,       // __vr_mag_dropped
    RF_AMMO_DROPPED = 16,     // __vr_ammo_dropped
    RF_NEEDS_PUMP = 32,       // __vr_needs_pump
    RF_NEEDS_RACK = 64,       // __vr_needs_rack
};
constexpr float SENTINEL = 54321.0f;
constexpr float NO_VALUE = 999.0f;   // only for slots whose real values stay well below it (room space, axes)

enum Hand : int { LEFT = 0, RIGHT = 1 };

void install();                    // finds the mailbox method and hooks it (call once, from the game thread)
bool live();                       // array attached and the headset + controllers active
bool held(Slot s);                 // button held this frame
bool pressed(Slot s);              // went down this frame (edge)
void frame_begin();                // snapshot buttons for edge detection; once per frame, before any feature
// a rumble for the Lua to fire on its next pass; two requests in one pass keep the stronger and the longer
void rumble(Hand h, float amplitude, float seconds, float hz);
float view(Slot s);                // read a slot NOW (not the frame-start snapshot); NO_VALUE if not attached
Vec3 view_vec3(Slot s);
bool flag(Slot s);                 // view(s) > 0.5, false when not attached
void put(Slot s, float v);         // write a slot the Lua reads
inline bool has(float v) { return v < NO_VALUE * 0.5f; }

Quat view_quat(Slot s);
Vec3 hand_pos(Hand h);             // controller position, room space (frame-start snapshot)
Vec3 hmd_pos();
Quat hmd_rot();
// room <-> game world, through the camera (the camera is the headset in the world): false when not attached
bool room_to_world(Vec3 room, Vec3& world);
bool world_to_room(Vec3 world, Vec3& room);
bool world_dir_to_room(Vec3 world_dir, Vec3& room_dir);
bool room_dir_to_world(Vec3 room_dir, Vec3& world_dir);
bool room_rot_to_world(Quat room_rot, Quat& world_rot);

} // namespace vn::bridge
