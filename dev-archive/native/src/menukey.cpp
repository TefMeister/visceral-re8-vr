// menukey.cpp -- see menukey.h.
#include "menukey.h"

#include <windows.h>

#include "bridge.h"

namespace vn::menukey {
namespace {
constexpr WORD MENU_KEY = VK_INSERT;   // REFramework's "Default Menu Key: Insert" (its overlay says so)
}

void frame() {
    if (!bridge::flag(bridge::S_MENU_KEY)) return;
    bridge::put(bridge::S_MENU_KEY, 0.0f);
    INPUT in[2] = {};
    in[0].type = INPUT_KEYBOARD;
    in[0].ki.wVk = MENU_KEY;
    in[0].ki.wScan = static_cast<WORD>(MapVirtualKeyW(MENU_KEY, MAPVK_VK_TO_VSC));
    in[0].ki.dwFlags = KEYEVENTF_EXTENDEDKEY;   // Insert is an extended key
    in[1] = in[0];
    in[1].ki.dwFlags = KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP;
    SendInput(2, in, sizeof(INPUT));
}
}  // namespace vn::menukey
