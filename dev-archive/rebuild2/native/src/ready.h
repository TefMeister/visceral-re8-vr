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

void refresh();
const Snapshot& now();

} // namespace vr8::ready
