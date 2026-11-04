// menukey.h -- opens REFramework's own menu on request from Lua (2026-11-04).
// Tefa: "the kitchen can be reframework full ui": the VR Options Emporium's fourth card (the Duke's Kitchen) opens
// REFramework's full menu. REFramework's Lua API can only ask whether the menu is open (reframework:is_drawing_ui()),
// not open it, so the Lua writes bridge slot S_MENU_KEY = 1 and this presses the menu key (Insert) once and clears it.
#pragma once

namespace vn::menukey {
void frame();   // once per game frame, after bridge::frame_begin()
}
