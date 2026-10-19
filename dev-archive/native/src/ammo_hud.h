// ammo_hud.h -- the remaining-ammo counter pinned to the right hand: port step 3 of Andyalpa's Hands Off pack
// (re8_vr_ammo_hud.lua, 1,410 lines, credit: Andyalpa), moved into the plugin 2026-10-19. Same behaviour, same settings
// file (reframework/data/re8_vr/re8_vr_ammo_hud.json, written by the menu Lua, read here whenever it changes):
//   display "weapon"  the game's own counter (app.GUIRemainAmmo) is kept open, switched to a world-space view and its
//                     transform written each frame at the right hand (IK target) plus the offsets / turn / scale
//   display "default" the game's counter is left alone; "off" = hidden
// Hidden with the knife, bare hands (the holster's __re8_bare_hands) and while a pause / inventory menu is open; after
// a menu closes, the headset comes back or the counter stops drawing, it is reset and reopened (his "recover").
// What the Lua read from other scripts comes through the bridge: __re8_bare_hands, __vr_is_interaction_blocked(),
// __vr_reloaded_master_enabled. The menu's buttons (open now, recover, re-resolve) arrive as a numbered command.
#pragma once
#include "common.h"

namespace vn::ammo_hud {

void frame();                                   // UpdateBehavior pre
bool pre_gui_draw(void* element, void* context);   // on_pre_gui_draw_element: false = do not draw it

} // namespace vn::ammo_hud
