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
    S_ZONE_SHOW = 114,        // unused since 2026-10-30 (the spheres show as the left hand nears one; nothing read it)
    S_ZONE_SEQ = 115,         // WRITTEN BY THE LUA MENU: +1 whenever zones.json was saved (zones.cpp re-reads it)
    S_ZONES = 116,            // 116-140, WRITTEN BY THE PLUGIN: five zones x {x, y, z (world, m), radius (m), on}: the magazine grab,
                              // the well (where it goes in), the slide / pump / bolt (on = 1 slide, 2 pump, 3 bolt), the hand point tested
    S_ARC_CM = 141,           // WRITTEN BY THE LUA BRIDGE: how high (cm) the left hand arcs over the gun on its way onto / off the slide / pump / bolt (2026-10-25)
    S_PAIR_ACT = 142,         // 142-146, WRITTEN BY THE PLUGIN: the gun's hand pair nearest the left hand, its ACTIVATION sphere {x, y, z (world, m), radius, on} (pairs.h)
    S_PAIR_LAND = 147,        // 147-151, WRITTEN BY THE PLUGIN: always off since 2026-10-30 (the landing spot is no longer drawn)
    S_PAIR_ACTIVE = 152,      // WRITTEN BY THE PLUGIN: the number of the pair holding the left hand now, 0 = none
    S_LEFT_SPOT = 153,        // WRITTEN BY THE PLUGIN: where the left hand is, for Hand Poser's pose per spot (pairs.cpp):
                              // 1000+N on pair N's landing spot, 2000+N inside pair N's activation sphere, 3 slide/pump/bolt, 4 magazine, 0 none
                              // 2026-11-08: 11 slide/pump/bolt at the back (after its click, until home), 12 the same for a slide from the left,
                              // 13 a magazine carried in the left hand
    S_ZONES2 = 154,           // 154-168, WRITTEN BY THE PLUGIN: three more zones x {x, y, z, r, on}: the HANDLE, the DRUM, the INSERT
                              // point (zones.h, 2026-10-27); the left hand's spot (153) gains 5 handle, 6 drum, 7 insert;
                              // 2026-10-28: 8 a pistol's slide taken from the gun hand's left (3 stays the right side)
    S_ZONE_SLIDE_LEFT = 169,  // 169-173, WRITTEN BY THE PLUGIN: the slide's LEFT-side sphere {x, y, z, r, on} (2026-10-28, pistols;
                              // zones.h SLIDE_LEFT, drawn as zone 23 by visceral_re8_zones.lua); the left hand's spot (153) gains
                              // 9 rounds from the pouch
    S_AUTO_EXPOSURE_ON = 174, // 2026-10-29: 1 = the game keeps its own automatic brightness (visceral_re8_menu.lua tick box); 0 or unset = ours keeps it off (exposure.cpp)
    // 2026-10-31 (Tefa: "the shotgun shell size and positioning in re8, how do i change that"): the round in the left hand,
    // per gun, from the menu "Visceral RE8 reload" (visceral_re8_bridge.lua, saved in visceral_re8/shell_hold.json):
    S_SHELL_HOLD = 175,       // 175-181, WRITTEN BY THE LUA MENU: move 1-3 (cm, the hold's own axes), turn 1-3 (deg), size (percent, 0 = unset = 100)
    S_RIGHT_SPOT = 184,       // 2026-11-02, WRITTEN BY THE PLUGIN: where the right hand is docked, for Hand Poser: 1 the Wolfsbane's cover, 2 the rifle's bolt (pairs.cpp); 3 over the hammer; 4 the bolt at the back (2026-11-08)
    S_GATE_HOLD = 183,        // 2026-11-01, WRITTEN BY THE PLUGIN: 1 = the Wolfsbane is held by the left hand while the right hand loads it (gate.cpp): no holster grab
    // 2026-11-05 (Tefa: "throwing away a used mag ... that sound would also play from where it lands"), reload.cpp ->
    // visceral_re8_magthrow.lua: a magazine let go of (or out of the magwell) is handed to the Lua, which flies a copy of it
    S_MAGTHROW_SEQ = 187,     // WRITTEN BY THE PLUGIN: +1 per magazine handed over (written LAST, after the numbers below)
    S_MAGTHROW_ROOT_POS = 188,  // 188-190: where the gun's root would be so its seated magazine sits where the magazine is now (world)
    S_MAGTHROW_ROOT_ROT = 191,  // 191-194: that root's rotation (x, y, z, w)
    S_MAGTHROW_PIVOT = 195,   // 195-197: the magazine's own point (world), the copy turns about it
    S_MAGTHROW_VEL = 198,     // 198-200: its speed when let go (m/s, world)
    S_MAGTHROW_PART = 201,    // the gun mesh's magazine part number (the copy shows only that part)
    S_MAGTHROW_ROUNDS = 203,  // 2026-11-05: rounds in the magazine handed over (its own count; the copy shows its rounds parts only when > 0)
    S_MAGTHROW_SECOND = 204,  // the gun's second magazine part (-1 none), + 1000 when the gun shows it right now (the copy shows it too)
    S_MAGTHROW_VANISH = 205,  // 205-212: the parts that vanish when the magazine is empty (the rounds), -1 = unused (magdisp.cpp)
    S_MAGTHROW_ACK = 202,     // WRITTEN BY THE LUA: the SEQ it made a copy for; the plugin then hides the gun's own falling magazine
    S_CLIP_PLAYING = 186,     // 2026-11-05, WRITTEN BY THE PLUGIN: a finger clip plays (shellclip.cpp): +1 the left hand, +2 the right; Hand Poser stands aside for that hand
    S_MENU_KEY = 185,         // 2026-11-04, WRITTEN BY THE EMPORIUM SCRIPT: 1 = press REFramework's menu key once (menukey.cpp), the plugin clears it
    S_GAME_SFX_SEQ = 182,     // 2026-11-01, WRITTEN BY THE SOUNDS SCRIPT: +1 on every gun sound the game itself plays (not ours, not footsteps)
    // 2026-11-09 (b104, Tefa: Hand Poser must "read all the grip zones we have in the game for all the guns and holster zones for
    // both left and right hand"): 214 / 215 WRITTEN BY THE HOLSTER SCRIPT: the holster spot the left / right hand is inside (0 none,
    // 1 right shoulder, 2 right hip, 3 left hip, 4 left shoulder); 216 WRITTEN BY THE PLUGIN: the gun zone the RIGHT hand is in while
    // the LEFT hand holds the gun (the Wolfsbane, the rifle's bolt by RG): 0 none, 10 + zones::Key as S_LEFT_AREA. pairs.cpp
    S_LEFT_HOLSTER = 214, S_RIGHT_HOLSTER = 215, S_RIGHT_AREA = 216,
    // 2026-11-11 (Tefa: "can you get 2 shotgun shells to show up for the shotgun ... so they disappear one after another when
    // inserted"), reload_pose.cpp -> visceral_re8_shell2.lua: the gun has ONE loose shell joint, so the second shell of a grab is
    // a copy of the gun's mesh with only its shell left in sight, drawn beside the first by the Lua. All WRITTEN BY THE PLUGIN:
    S_SHELL2_ON = 217,        // S_FRAME + 1 of the frame it was last wanted (a second shell is in the left hand); stale = not wanted
    S_SHELL2_POS = 218,       // 218-220: where the FIRST shell is drawn (world)
    S_SHELL2_ROT = 221,       // 221-224: its turn (x, y, z, w)
    S_SHELL2_SIZE = 225,      // its size against the game's (1 = the game's; the menu's "size" slider)
    S_LEFT_AREA = 213,        // WRITTEN BY THE PLUGIN (2026-11-09, Tefa: "make Hand Poser say ... that the left hand is now in for
                              // example left side slide activation area"): WHICH area a free left hand is in while S_LEFT_SPOT says
                              // "ready" (14): 0 none, 1 the pouch, 10 + zones::Key (10 magazine, 11 well, 12 the slide / pump / bolt,
                              // 14 front grip, 15 handle, 16 drum, 17 insert point, 18 the slide from the left). pairs.cpp
    S_COUNT = 175,            // the button snapshot's length (unchanged: the slots from 175 on are read live with view()); the Lua array is 182 long            // 2026-10-29: 174 the brightness tick box; 2026-10-27: 154-168 the handle / drum / insert zones; 2026-10-26: 153 the left hand's spot; 2026-10-25: 142-152 the hand pairs; 136-140 the FRONT GRIP zone
};
enum Sfx : int {               // S_SFX_CODE values
    SFX_SLIDE_BACK = 1, SFX_SLIDE_FORWARD = 2, SFX_PUMP_BACK = 3, SFX_PUMP_FORWARD = 4,
    SFX_BOLT_UP = 5, SFX_BOLT_BACK = 6, SFX_BOLT_FORWARD = 7, SFX_BOLT_DOWN = 8,
    SFX_MAG_OUT = 9, SFX_MAG_IN = 10, SFX_SHELL_IN = 11,
    SFX_DRY_FIRE = 12,   // (on the Wolfsbane the sounds script plays its EJECT_BULLET for 12: a spent case out, gate.cpp)
    SFX_DRUM_TURN = 13,  // 2026-11-06: the Wolfsbane's drum turned by LT (its MVT_CYLINDER_ROLL)
   // 2026-10-31 (Tefa: the game's own empty click, not our beep)   // 2026-10-24 (Tefa: "not the mag being inserted")
};
enum Experiment : int {        // S_EXPERIMENT bits (menu "Visceral RE8 reload" -> "Experiments")
    EX_MAG_HIDE_AT_DROP = 1,   // the old way: the gun's own magazine display switched off the moment the magazine drops
    EX_MAG_NO_SECOND = 2,      // do NOT move "Magazine_second" with "Magazine"
    EX_NO_SMOOTH = 4,          // no smoothing of the left hand going onto / off the gun
    EX_GAME_RELOAD = 8,        // the game's own reload is let through (its motion plays the gun's handling sounds, learned by the Lua)
};
void sfx(Sfx code);
float last_sfx_s();   // 2026-11-06: when sfx() last asked (now_s), so foley.cpp lets our own replays through
bool lua_has_sfx(Sfx code);   // the sounds script has a game sound for this code            // ask the Lua for a handling sound (plays the plugin's wav itself when the Lua has none)
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
// 2026-11-08 (Tefa, the LEMI slide: "if LG is still being held after it comes off, it must not do anything until released and
// pressed again"): from now until LG is let go, held(S_LGRIP) and pressed(S_LGRIP) say "up" to every feature of the plugin, and
// the grip script is told to keep off (handstate.cpp's S_GRIP_VETO). Cleared by itself the first frame LG is up.
void swallow_lgrip(const char* why);
bool lgrip_swallowed();
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
