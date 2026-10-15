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

} // namespace vn::settings
