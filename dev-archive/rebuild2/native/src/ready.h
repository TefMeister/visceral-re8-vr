// ready.h -- rebuild 2 (design item 4 + RULE 9): the player, and the ONE "player ready" flag every part reads.
//
// Found the way praydog's RE8VR.cpp finds it (app.PropsManager's <Player>k__BackingField), so it is the same
// object his `re8vr.player` is. Refreshed once per frame at UpdateBehavior pre; everything later in the frame
// reads the snapshot. Nothing here is kept across a player change: `generation` goes up when the player object
// changes, and every part that keeps joints or poses drops them when it sees a new number (rule 7).
#pragma once
#include "base.h"

namespace vr8::ready {

struct Snapshot {
    MO* player = nullptr;        // via.GameObject
    MO* transform = nullptr;     // its via.Transform
    unsigned generation = 0;     // +1 whenever `player` becomes a different object (or goes away)
    // RULE 9: true only when the player exists, the bridge is live, the headset and controllers are in use, no
    // cutscene owns the player and praydog's layer says the hands are the player's (not jacked, no motion play).
    bool hands_are_players = false;
};

// the main camera's transform, the way the scripts' sdk.get_primary_camera() finds it (nullptr when there is none)
MO* camera_transform();

// how fast the player's own spot moves, level, metres a second, and the time since the last picture: worked out
// once per picture by render_tick() (PrepareRendering post), read by the lean fix and the recorders
struct Pace { float speed_mps = 0.0f; float dt = 0.011f; Vec3 at{}; Quat turn{0, 0, 0, 1}; bool ok = false; };
void render_tick();
const Pace& pace();

void refresh();
const Snapshot& now();

} // namespace vr8::ready
