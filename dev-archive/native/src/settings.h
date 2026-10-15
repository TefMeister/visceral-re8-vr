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

} // namespace vn::settings
