// turn.h -- the body turns like RE2's, through the GAME'S OWN body-follow rule (2026-10-29). See turn.cpp.
#pragma once

namespace vn::turn {

// Once a frame, from the plugin's frame step (after player::now()). Reads the game's turn settings once and logs them,
// and, while the Lua menu's body-turn box is ticked, writes Tefa's deadzone and speed into them for the moment's state.
void frame();

// True while this module drives the body (body.cpp's joint rewriting then stays out of the way).
bool active();

} // namespace vn::turn
