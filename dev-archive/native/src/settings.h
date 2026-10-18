// settings.h -- every number the Village native code uses, named, in one place (code-shape rule, 2026-09-17).
// Ported numbers keep Andyalpa's names and values from the Hands Off pack (dev-archive/original-lua/).
#pragma once
#include <cstddef>

namespace vn::settings {

// bridge.cpp
constexpr size_t MAILBOX_LOG_COUNT = 5;          // how many mailbox candidates to log on the first frame

// haptics.cpp -- re8_vr_haptics.lua, top of file
constexpr float HAP_GRIP_AXIS_ON = 0.65f;        // GRIP_AXIS_ON: a grip axis at or past this counts as held
constexpr float HAP_TWO_HAND_ENTER_M = 0.32f;    // TWO_HAND_ENTER_M: hands this close with the left grip = two-handed
constexpr float HAP_TWO_HAND_EXIT_M = 0.48f;     // TWO_HAND_EXIT_M: ...and stay two-handed until this far apart
constexpr float HAP_NO_DISTANCE = 99.0f;         // "no hand positions" distance, as the Lua returns
constexpr float HAP_FAR_DISTANCE = 90.0f;        // a re8vr hand distance at or past this is treated as missing
constexpr int HAP_SHOOT_CONTEXT_FRAMES = 2;      // a game rumble order keeps "shooting" on for this many frames
constexpr int HAP_TWO_HAND_EVERY_FRAMES = 2;     // the two-hand state is refreshed every this many frames
constexpr float HAP_AMP_MAX = 1.5f;              // scaled amplitude is clamped to 0..this
constexpr float HAP_PULSE_ON_MIN_S = 0.008f;     // auto-fire pulse: shortest "on" part of a tick
constexpr float HAP_PULSE_OFF_MIN_S = 0.020f;    // auto-fire pulse: shortest "off" part of a tick
constexpr float HAP_PULSE_DUR_MIN_S = 0.010f;    // auto-fire pulse length is clamped to these two
constexpr float HAP_PULSE_DUR_MAX_S = 0.030f;
constexpr float HAP_PAD_HZ = 1.0f;               // praydog's re8_vr.lua passes frequency 1 for the game's own rumble

// haptics.cpp defaults, used until the menu Lua sends the saved file (re8_vr_haptics.lua CFG, "medium" = 0.80)
constexpr bool HAP_DEF_ENABLED = true;
constexpr bool HAP_DEF_GATE_LEFT = true;
constexpr float HAP_DEF_SCALE = 0.80f;
constexpr bool HAP_DEF_AUTO_PULSE = true;
constexpr float HAP_DEF_ON_S = 0.018f;
constexpr float HAP_DEF_OFF_S = 0.070f;
constexpr float HAP_DEF_MAX_DUR = 0.018f;

// recoil.cpp -- re8_vr_recoil.lua (numbers that are not in its saved file; the saved ones are in recoil.cpp's Cfg)
constexpr float REC_SUPPORT_HAND_M = 0.35f;      // SUPPORT_HAND_DISTANCE: hands this close (with the left grip) = two-handed
constexpr float REC_FADEOUT_S = 0.045f;          // RECOIL_FADEOUT_DURATION: the last bit of spring blends out over this
constexpr float REC_DT_MAX_S = 0.05f;            // a frame's step is clamped to this
constexpr float REC_DT_FIRST_S = 1.0f / 60.0f;   // the step used before any recoil time exists
constexpr int REC_KICKS_PER_FRAME_MAX = 10;      // shots applied in one frame at most
constexpr int REC_PENDING_MAX = 20;              // shots queued between frames at most
constexpr float REC_ATTACK_MIN_S = 0.001f;       // attack_duration floor
constexpr float REC_SUSTAIN_WINDOW_MIN_S = 0.01f;   // sustained_window floor
constexpr float REC_SETTLE_MULT_MIN = 1.0f;      // spring_settle_mult floor
constexpr float REC_EXPONENT_MIN = 0.1f, REC_EXPONENT_MAX = 1.0f;   // mult_exponent clamp
constexpr float REC_AUTO_SCALE_MIN = 0.05f;      // auto_scale floor
constexpr float REC_MEDIUM_BLEND = 0.42f;        // a "medium" weapon's one-hand kick: light + (heavy - light) * this
constexpr float REC_WEAPON_INTENSITY_MIN = 1.0f, REC_WEAPON_INTENSITY_MAX = 4.0f;   // per-weapon slider range
// spring channels: {settle_start, snap_pos, snap_vel} -- below settle_start the damping rises toward settle_mult x;
// below both snap values the channel is set to rest (spring_channel_damping)
struct SpringChannel { float settle_start, snap_pos, snap_vel; };
constexpr SpringChannel REC_CH_POS{0.002f, 0.00003f, 0.0006f};
constexpr SpringChannel REC_CH_PITCH{0.04f, 0.007f, 0.06f};
constexpr SpringChannel REC_CH_YAW{0.025f, 0.005f, 0.05f};
// the spring counts as settled (start the fade-out) below all three
constexpr float REC_DONE_POS = 0.00003f, REC_DONE_ROT = 0.00012f, REC_DONE_VEL = 0.0005f;
constexpr float REC_ZERO = 1e-7f;                // "no offset at all"
constexpr int REC_CFG_CHECK_FRAMES = 60;         // how often the saved file's time is checked for a menu change

// reload.cpp / rack.cpp -- moved over from Visceral RE7 / RE2 (2026-10-18). Village has no per-weapon numbers yet, so the
// places are measured from the controllers in the room instead of from the gun's own parts.
constexpr bool RELOAD_ON = true;
constexpr float RELOAD_SLIDE_SEC = 0.19f;        // the magazine slides out of the magwell (when its joint is known)
constexpr float RELOAD_FALL_SEC = 0.5f;          // then falls this long
constexpr float RELOAD_FALL_M = 1.2f;            // this far
constexpr float RELOAD_INSERT_SEC = 0.19f;       // a new one slides in
constexpr float RELOAD_MAG_DROP_M = 0.09f;       // how far below its seat the magazine slides out (gun's local -Y, a guess)
constexpr float RELOAD_DOCK_COOLDOWN_SEC = 0.35f;
constexpr float RELOAD_GRAB_COOLDOWN_SEC = 0.45f;   // Andyalpa's ammo_left_cooldown
// where a magazine / shell goes in, from the right controller in the room: pistols at the hand, long guns ahead of it
constexpr float DOCK_PISTOL_M = 0.20f;           // left controller this close to the right one = in (0.13 never reached in
                                                 // the headset, 2026-10-18: the controllers' rings meet before that)
constexpr float DOCK_LONG_AHEAD_M = 0.20f;       // long guns: the magwell / loading port this far ahead along the barrel
constexpr float DOCK_LONG_M = 0.14f;             // ... and the left controller this close to that point = in
constexpr float LEFT_HIP_POUCH[3] = {-0.20f, -0.62f, 0.02f};   // our own pouch spot when Andyalpa's ammo spot is off (RE2's left hip)
constexpr float POUCH_ENTER_M = 0.15f, POUCH_LEAVE_M = 0.22f;
constexpr float RELOAD_GRAB_BUZZ_AMP = 0.35f, RELOAD_GRAB_BUZZ_SEC = 0.05f;
constexpr float RELOAD_INSERT_BUZZ_AMP = 0.45f, RELOAD_INSERT_BUZZ_SEC = 0.05f;
constexpr float RELOAD_DENY_BUZZ_AMP = 0.2f, RELOAD_DENY_BUZZ_SEC = 0.15f;
constexpr float RELOAD_BUZZ_HZ = 160.0f;
// the magazine drop / in-hand animation on joint "_04" (RE2 / RE7's magazine name): off until a joint log shows which
// Village joint is the magazine; the gun's own switchMagazineDisp hides it meanwhile
constexpr bool MAG_JOINT_ANIMATE = false;
constexpr int JOINT_LOG_MAX = 40;                // joints of a newly held gun written to the log, at most
// the hold of a magazine in the left hand (Andyalpa's RE7 handgun hold; Village's own is for Tefa's poses to decide)
constexpr float MAG_HOLD[6] = {0.104f, -0.039f, 0.053f, 100.5f, -11.5f, 131.5f};   // offset (m), yaw / pitch / roll (deg)

// rack.cpp: slide / bolt / charging handle and pump (RE2 b165/b166 gesture)
constexpr float RACK_GRAB_M = 0.16f;             // left controller this close to the right one's gun line = can take hold
constexpr float RACK_GRAB_AHEAD_MAX_M = 0.70f;   // ... and no further ahead along the barrel than this
constexpr float RACK_GRAB_BEHIND_M = 0.10f;      // ... or behind the gun hand than this (a pistol slide sits over the hand)
constexpr float RACK_PULL_M = 0.08f;             // controller travel for a full pull (Andyalpa's pull_dist)
constexpr float RACK_RETURN_M = 0.06f;           // and forward again for a full return
constexpr float RACK_FOLLOW = 0.92f;             // the slide follows the hand by this much per frame
constexpr float RACK_SPRING_STEP = 0.2f;         // let go mid-way: travel lost per frame as it springs back
constexpr float PUMP_RETURN_SEC = 0.2f;          // the pump handle returning by itself after LT is let go
constexpr float RACK_BUZZ_AMP = 0.45f, RACK_BUZZ_SEC = 0.05f;
constexpr float SLIDE_BACK_M = -0.045f;          // the slide joint fully back, local Z from rest (when the joint is known)
constexpr float PUMP_BACK_M = -0.080f;

} // namespace vn::settings
