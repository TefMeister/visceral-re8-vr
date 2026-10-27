// settings.h -- every number the Village native code uses, named, in one place (code-shape rule, 2026-09-17).
// Ported numbers keep Andyalpa's names and values from the Hands Off pack (dev-archive/original-lua/).
#pragma once
#include <cstddef>
#include "common.h"

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

// ghosthand.cpp: record the hands for Ghost Hand BeG0nE while the headset is live (Tefa 2026-10-19: "log everything")
constexpr bool GHOST_HAND_ON = true;

// reload.cpp / rack.cpp -- moved over from the RE7 RELOADED mod / Visceral RE2 (2026-10-18). Village has no per-weapon numbers yet, so the
// places are measured from the controllers in the room instead of from the gun's own parts.
constexpr bool RELOAD_ON = true;
// eject.cpp (2026-10-24): a pump / bolt gun's spent shell leaves when the hand pulls the pump / bolt back, not at the shot
constexpr bool EJECT_BY_HAND = true;
constexpr float RELOAD_SLIDE_SEC = 0.19f;        // the magazine slides out of the magwell (when its joint is known)
constexpr float RELOAD_FALL_SEC = 0.5f;          // then falls this long
constexpr float RELOAD_FALL_M = 1.2f;            // this far
constexpr float RELOAD_INSERT_SEC = 0.19f;       // a new one slides in
constexpr float RELOAD_TARGET_REACH_M = 0.02f;   // the drawn wrist this close to its IK target = the arm reached it (measure then)
constexpr float RELOAD_MAG_DROP_M = 0.09f;       // how far below its seat the magazine slides out (gun's local -Y, a guess)
constexpr float RELOAD_DOCK_COOLDOWN_SEC = 0.35f;
constexpr float MAG_GRAB_M = 0.12f;               // (0.18 took the forestock grab too, 03:21)
// reload.cpp: the left hand (its IK target, where it was drawn) this close to the seated magazine, LG pressed = the hand goes onto
// it (LT then pulls it out). Last wear 2026-10-25 03:52: real grabs measured 0.080-0.118 m, so 0.12 is right
// 2026-10-25 (the last wear: the pulled magazine "jumps back in"; the log: clear at 0.126 m and "insert at 0.126 m (need 0.16)" the
// same frame, because the old clear distance (0.12) lay inside the insert distance). Tefa, 09:20: "can this be set so that LT must
// be pressed again for it to go back in, that would solve this problem for good". So a magazine pulled out by hand goes back in
// only on a fresh LT press while it is at the well; a fresh one from the pouch still seats by itself when brought to the gun
constexpr bool  INSERT_NEEDS_LT = true;
constexpr float INSERT_LT_MIN_SEC = 0.25f;        // the pull-out's own LT press (the same frame) never counts as the seat press
constexpr float RELOAD_GRAB_COOLDOWN_SEC = 0.45f;   // Andyalpa's ammo_left_cooldown
// where a magazine / shell goes in, from the right controller in the room: pistols at the hand, long guns ahead of it
constexpr float DOCK_PISTOL_M = 0.24f;           // left controller this close to the right one = in (0.13 never reached in
                                                 // the headset, 2026-10-18: the controllers' rings meet before that)
constexpr float DOCK_IN_FRONT_M = 0.15f;         // ... and the left controller at least this far in front of the headset
constexpr float DOCK_BELOW_HEAD_M = 0.55f;       // ... and no lower than this under it (the ammo spot is ~0.62 below)
constexpr float DOCK_LONG_M = 0.35f;             // (used only when the gun's own port joint is not found)
constexpr float DOCK_ITEM_M = 0.16f;             // long guns: the magazine / shell in the hand this close to its measured place
                                                 // on the gun (Tefa asked 0.10 on 2026-10-19; that run came to 0.138 / 0.107)
constexpr float LEFT_HIP_POUCH[3] = {-0.20f, -0.62f, 0.02f};   // our own pouch spot when Andyalpa's ammo spot is off (RE2's left hip)
constexpr float POUCH_ENTER_M = 0.15f, POUCH_LEAVE_M = 0.22f;
constexpr float RELOAD_GRAB_BUZZ_AMP = 0.35f, RELOAD_GRAB_BUZZ_SEC = 0.05f;
constexpr float RELOAD_INSERT_BUZZ_AMP = 0.45f, RELOAD_INSERT_BUZZ_SEC = 0.05f;
constexpr float RELOAD_DENY_BUZZ_AMP = 0.2f, RELOAD_DENY_BUZZ_SEC = 0.15f;
constexpr float RELOAD_BUZZ_HZ = 160.0f;
// the guns that open to load (breech.cpp, 2026-10-19): revolvers flick the cylinder out, the GM 79 drops its barrel
constexpr bool  BREECH_ON = true;
constexpr bool  BREECH_FLICK_ON = true;           // off = right B only
constexpr float BREECH_FLICK_DEG_S = 420.0f;      // the gun hand turning this fast about the flick axis = a flick (a guess: the log prints Tefa's fastest)
constexpr float BREECH_FLICK_LOG_DEG_S = 200.0f;  // turns this fast are logged once a second, to set the number above
constexpr float BREECH_FLICK_FOLLOW = 0.6f;       // smoothing of the turn rate per frame (1 = raw)
constexpr float BREECH_FLICK_COOLDOWN_SEC = 0.35f; // after opening / closing, no flick counts for this long (the hand coming back)
constexpr float BREECH_BUZZ_AMP = 0.5f, BREECH_BUZZ_SEC = 0.05f;
// the magazine drop / in-hand animation on joint "_04" (RE2 / RE7's magazine name): off until a joint log shows which
// Village joint is the magazine; the gun's own switchMagazineDisp hides it meanwhile
constexpr bool MAG_JOINT_ANIMATE = true;    // on since 2026-10-18 23:30: the joint is named "Magazine"
constexpr int JOINT_LOG_MAX = 40;                // joints of a newly held gun written to the log, at most
// the hold of a magazine in the left hand (Andyalpa's RE7 handgun hold; Village's own is for Tefa's poses to decide)
constexpr float MAG_HOLD[6] = {0.104f, -0.039f, 0.053f, 100.5f, -11.5f, 131.5f};   // offset (m), yaw / pitch / roll (deg)

// rack.cpp: slide / bolt / charging handle and pump (RE2 b165/b166 gesture)
// 2026-10-28 (Tefa: two spots on every pistol's slide): the left controller this far to the RIGHT of the right one, along the
// gun's own x, takes the slide's right-side hold; anything less, the left-side hold (0 = the gun hand's own line)
constexpr float SLIDE_SIDE_SPLIT_M = 0.0f;
constexpr float RACK_GRAB_M = 0.16f;             // left controller this close to the right one's gun line = can take hold
constexpr float RACK_GRAB_AHEAD_MAX_M = 0.70f;   // ... and no further ahead along the barrel than this
constexpr float RACK_GRAB_BEHIND_M = 0.10f;      // ... or behind the gun hand than this (a pistol slide sits over the hand)
constexpr float RACK_JOINT_GRAB_M = 0.14f;       // the left controller this close to the slide / pump joint = can take hold
// 2026-10-25 (the last wear, Tefa: "the bolt activation area is too large", "hand still gripped on the rifle grip handle alongside
// right hand"): the F2's bolt joint sits 13 cm from its magazine joint, and the bolt zone was measured from the CONTROLLER (which
// sits ~15 cm behind the drawn hand) while the magazine's is measured from the drawn hand, so every reach for the magazine that
// missed it by a few cm was taken by the bolt and the hand was held up at the bolt, beside the right hand. The bolt is now measured
// from the drawn hand (the left IK target, the same point as the magazine) and takes only close to its joint
constexpr float GRIP_ZONE_M = 0.10f;             // the FRONT GRIP zone: the left controller this close to the gun's kept grip spot = LG takes the grip (the grip script's 10 cm)
constexpr float RACK_BOLT_GRAB_M = 0.09f;        // the drawn left hand this close to the bolt joint = can take hold (the magazine wins within MAG_GRAB_M)
// zones.cpp (2026-10-25): the grab zones can be moved and resized from the menu (zones.json); this is the size of the drawn dot at the
// point the tests measure from (the drawn left hand, or the controller for the slide / pump)
constexpr float ZONE_HAND_MARK_M = 0.02f;
constexpr int   ZONE_FILE_CHECK_FRAMES = 20;
// numbered hand pairs (pairs.h, 2026-10-25): an activation sphere and a landing spot, set in the Grab Zones window
// 2026-10-27 the new gun parts (zones.h HANDLE / DRUM / INSERT): where they start and how big (guesses; Grab Zones moves them)
constexpr float HANDLE_ZONE_M = 0.08f; constexpr Vec3 HANDLE_OFF{-0.04f, -0.04f, 0.0f};   // below-left of the gun hand: the cupping hand
constexpr float DRUM_ZONE_M = 0.06f;   constexpr Vec3 DRUM_OFF{0.0f, 0.04f, 0.08f};      // a revolver's cylinder, above and ahead of the hand
constexpr float INSERT_ZONE_M = 0.07f; constexpr Vec3 INSERT_OFF{0.0f, 0.05f, 0.12f};    // the GM 79's breech
// 2026-10-27 the revolver's drum by hand (breech.cpp): dragged this far sideways (the left controller against the right, the
// gun's own left / right) it clicks open / shut; let go past this share of a closing drag it swings shut; the gun tipped
// this far muzzle-up with the drum open drops the spent casings (live rounds stay)
constexpr float DRUM_DRAG_M = 0.05f;
// the swing that closes the open drum (2026-10-27, Tefa: "the actual player hand swing ... andyalpa already had that implemented
// in re7 and re2"): Andyalpa's RE7 numbers (re7_vr_reload_ext.lua close_gesture_*): the gun hand over 35-170 ms, a swipe right
// (4 cm, 0.85 m/s, mostly sideways) or a kick up (5 cm, 1.15 m/s, mostly up), then 0.8 s before another counts
constexpr float SWING_WINDOW_MIN_S = 0.035f, SWING_WINDOW_MAX_S = 0.17f, SWING_COOLDOWN_S = 0.8f;
constexpr float SWING_RIGHT_M = 0.04f, SWING_RIGHT_MS = 0.85f, SWING_RIGHT_RATIO = 0.55f, SWING_RIGHT_MAX_UP = 0.4f;
constexpr float SWING_UP_M = 0.05f, SWING_UP_MS = 1.15f, SWING_UP_RATIO = 0.68f;
constexpr float DRUM_TILT_DEG = 30.0f;
constexpr float PAIR_ACT_R_DEFAULT_M = 0.06f;      // a pair's activation sphere when pairs.json gives no size
constexpr float PAIR_LAND_DOT_M = 0.015f;          // the landing spot is drawn as a dot this big (the hand lands on its centre)
constexpr float PAIR_FILE_CHECK_S = 1.0f;          // how often pairs.json's write time is checked
constexpr float PAIR_BUZZ_AMP = 0.35f, PAIR_BUZZ_SEC = 0.05f, PAIR_BUZZ_HZ = 160.0f;   // a short tick in the left hand at a take      // how often zones.json's write time is checked (a save from the Grab Zones window)
                                                 // (0.20 until 2026-10-24: Tefa "hand must not go straight onto the slider or the bolt after
                                                 // inserting a mag, there has to be a tighter zone"; it also needs a fresh LG press now)
constexpr float RACK_GRAB_ANY_M = 0.30f;          // ... or simply this close to the right controller (the gun-line test may be off)
constexpr float RACK_PULL_M = 0.08f;             // controller travel for a full pull (Andyalpa's pull_dist)
constexpr float RACK_RETURN_M = 0.06f;           // and forward again for a full return
constexpr float RACK_FOLLOW = 0.92f;             // the slide follows the hand by this much per frame
constexpr float RACK_SPRING_STEP = 0.2f;         // let go mid-way: travel lost per frame as it springs back
constexpr float PUMP_RETURN_SEC = 0.2f;          // the pump handle returning by itself after LT is let go
constexpr float RACK_BUZZ_AMP = 0.45f, RACK_BUZZ_SEC = 0.05f;
// the bolt action (Tefa 2026-10-19: "turn the bolt up, pull backwards, then a gun click sound must play to signify that i can
// now push the bolt back forward and then back down to lock it in", after every round): the turns are read from the left
// hand going up / down against the right one (the controllers' turn readings jumped around, 2026-10-19)
// 2026-10-24: the lift and the drop are done by the bolt itself now (Tefa), with LT held to lift it
constexpr float BOLT_LIFT_SEC = 0.12f;           // the bolt turning up (LT held) and back down (once home), by itself
constexpr float BOLT_TURN_DEG = -60.0f;          // how far the bolt joint turns about the barrel when up (+60 went into the gun, 2026-10-19)
constexpr float BOLT_HOME = 0.08f;               // travel at or under this = pushed home
constexpr float BARREL_MUZZLE_MIN_M = 0.05f;     // the muzzle joint at least this far from the gun's origin = a usable barrel line
constexpr float SLIDE_BACK_M = -0.045f;          // the slide joint fully back, local Z from rest (when the joint is known)
constexpr float PUMP_BACK_M = -0.080f;

// smooth.cpp (2026-10-24): the left hand eased onto and off the gun, the slide, the pump and the bolt
constexpr float SMOOTH_DOCK_SEC = 0.15f;
constexpr float SMOOTH_ARC_SEC = 0.30f;           // the same ease when the hand ARCS over the gun onto / off the slide / pump / bolt (slower, so the arc is a path, not a blink)
constexpr float SMOOTH_ARC_MAX_M = 0.30f;         // the arc's height is clamped to this
constexpr float SMOOTH_TOWARD_M = 0.01f;          // a later solve asking this much closer to the left controller = an undo (drawn)
constexpr float FREE_TURN_DEVIATION_RAD = 0.35f;  // smooth.cpp: the free hand's target turned this far (20 deg) from its controller prediction = a dock
constexpr float FREE_DEVIATION_M = 0.04f;         // smooth.cpp: the free hand's target this far from its controller prediction = a dock (put back)
constexpr int   FREE_LEARN_FRAMES = 5;            // free frames in a row before the controller offset is learned from them
constexpr float FREE_LEARN_RATE = 0.05f;          // how fast the learned offset follows
constexpr float FREE_OFFSET_MAX_M = 0.35f;        // a learned offset longer than this is not believed
constexpr float SMOOTH_LATE_DOCK_M = 0.15f;       // a later solve of the frame asking this close to the first answer = a late dock: held back

// rack.cpp (2026-10-24, Tefa: "gun goes through the left wrist not the palm for LEMI and the shotgun"): the IK target is the
// wrist, so on the slide and the pump the hand is moved back by the wrist-to-palm offset (L_Hand -> L_Palm, measured live)
constexpr bool PALM_ON_SLIDE = true;
constexpr bool SHELL_WORLD_WRITE = true;          // 2026-10-24: the pouch shell is placed in the world (off = the old gun-local write)
constexpr float SHELL_HOLD_DOWN_M = 0.07f;       // a shotgun shell from the pouch sits this much lower in the world than the
                                                 // magazine hold (Tefa 2026-10-24: "shell needs to be lowered about 7 cm for now")
constexpr float PALM_MEASURE_REACH_M = 0.02f;    // the drawn wrist this close to its target = the arm reached it: measure the palm then

// body.cpp (2026-10-24, Tefa idea 6): the drawn body lags the look / walk direction like Visceral RE2's
constexpr bool  BODY_TURN_ON = true;
constexpr float BODY_TURN_GAIN = 3.0f;            // turn rate = gain x the remaining angle (per second): big lags close fast
constexpr float BODY_TURN_MIN_DEG_S = 40.0f;      // and never slower than this, so a turn finishes (aiming)
// 2026-10-25 (Tefa): "body rotate on standing still after hmd has moved either right 60 degrees or left 60 degrees, straight
// forward is 0 then. when walking it's 45 degrees and when running 30"
constexpr float BODY_STAND_DEADZONE_DEG = 60.0f;  // standing: the head may look this far off the body before the body comes round to it
constexpr float BODY_WALK_DEADZONE_DEG = 45.0f;
constexpr float BODY_RUN_DEADZONE_DEG = 30.0f;
constexpr float BODY_RUN_MIN_MPS = 2.4f;          // moving faster than this = running
constexpr float BODY_FOLLOW_GAIN = 1.0f;          // the catch-up: gain x the remaining angle per second (slow), floor BODY_FOLLOW_MIN_DEG_S
constexpr float BODY_FOLLOW_MIN_DEG_S = 20.0f;
constexpr bool  BODY_ALL_JOINTS = true;           // 2026-10-25: the root alone never drew; turn every joint but the arms and the head
constexpr float BODY_MAX_OFFSET_DEG = 100.0f;     // the drawn body never further than this from the player transform
constexpr float BODY_WALK_MIN_MPS = 0.35f;        // moving faster than this = walking: the body faces the travel
constexpr float BODY_BACKPEDAL_DEG = 100.0f;      // travel further than this from the look = back-pedalling: face the look
constexpr int   BODY_MAX_JOINTS = 256;

// fingers.cpp (2026-10-24, Tefa): the left hand opens a little in a grab area (slide / pump / bolt, the gun, the pouch)
constexpr bool  FINGER_OPEN_ON = true;
constexpr float FINGER_OPEN_AMOUNT = 0.45f;       // how far toward the straight rest pose (0 = as animated, 1 = fully open)
constexpr float FINGER_OPEN_SEC = 0.25f;          // the time to open, and to close again
constexpr bool  NODOCK_ON = true;                 // nodock.cpp: the game's own left-hand dock is off while LG is up
constexpr int   NODOCK_FAKE_JOINT = 0;            // the joint index answered instead of the left wrist: 0 = the root, at the feet
constexpr float FINGER_OPEN_RAMP_M = 0.14f;       // the hand starts opening this far outside the grab zone, fully open at its edge

} // namespace vn::settings
