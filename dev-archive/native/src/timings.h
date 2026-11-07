// timings.h -- the mod's named seconds and sizes, tunable while the game runs (2026-11-07, Fable).
//
// Tefa, 2026-11-07: "something that lets me tune the weapons timings, like you did with the bullet cover yesterday". Until now
// every timing was a constexpr in settings.h (one rebuild per try) or a one-off key in lid_swing.json. Now each one is a row of
// this table: the settings.h number stays the default; reframework/data/visceral_re8/timings.json ({"hammer_press_s": 0.3, ...}),
// written by the Animation & Timing window (animation-timing-vr), overrides it and is re-read when the file changes. The window
// learns the rows (key, default, unit, words) from timings_known.json, which this file writes at the first frame and after every
// re-read, with the value in force. A key missing from timings.json = the default. Delete the file = everything default.
#pragma once

namespace vn::timings {

enum Key {
    COVER_SWING_S,     // the loading cover's swing open / shut (breech.cpp; lid_swing.json "sec" is the older knob, this wins when set)
    LIFT_S,            // the right thumb's lift over the hammer before the cover opens, and back (gate.cpp)
    PRESS_S,           // LT's press on the hammer, down and back up
    PRESS_CM,          // how far the palm goes down in that press
    CYL_TURN_S,        // the drum's one-chamber turn
    GLIDE_S,           // a hand gliding onto its place on the gun
    RETURN_S,          // the right hand back onto the grip before the thumb shuts the cover
    STAY_GLIDE_S,      // the left hand from the drum to its hold after loading
    HANDOVER_S,        // the gun eased back onto the right controller
    DROP_S,            // LG let go mid-way: the gun back onto the right hand
    FLICK_S,           // the right thumb's flick at the cover
    CLIP_BLEND_S,      // a finger clip blended in from / out to the hand's pose
    CASE_AT_OPEN_S,    // the case at the cover comes out this long after the cover starts opening
    CASE_AFTER_TURN_S, // the case starts out this long after the drum's turn has ended
    CASE_SLIDE_S,      // its slide out of the chamber, back through the cover
    CASE_FALL_S,       // its fall, then it is gone
    INSERT_REACH_S,    // the round from the hand to just behind the cover
    INSERT_PUSH_S,     // then pushed in
    HELD_FOLLOW_S,     // the gun in the left hand follows it with this smoothing
    LOAD_EASE_S,       // the hand eased between the drum and the loading place
    KEY_COUNT
};

float v(Key k);        // the value in force (timings.json's, else the default); seconds, or cm for PRESS_CM
bool has(Key k);       // true when timings.json sets it
void frame();          // once a frame (UpdateBehavior pre): re-read timings.json when it changed, write timings_known.json

} // namespace vn::timings
