// zones.h -- the grab zones, visible and adjustable (2026-10-25, Tefa: "is there any way I can visibly set them, how big they
// are, where they are on the gun ... a helper program that translates numbers into actual sliders and movable areas that ride
// the gun all the time"). Every place the left hand can take hold is a sphere riding the gun: where it sits (an offset from its
// anchor joint, in the gun's own axes) and how big it is. The numbers come from reframework/data/visceral_re8/zones.json
// (per gun, over a default, over the built-in settings.h values); the menu Lua (lua/visceral_re8_zones.lua) edits that file
// with sliders and draws each zone where THIS code tests it (bridge slots S_ZONES), so what is seen is what is used.
#pragma once
#include "common.h"

namespace vn::zones {

enum Key : int { MAG = 0, WELL = 1, PART = 2, HAND = 3, COUNT = 4 };   // the order of the bridge slots
enum PartKind : int { PK_SLIDE = 1, PK_PUMP = 2, PK_BOLT = 3 };

struct Zone { Vec3 off{0, 0, 0}; float r = 0.0f; };

void frame();                                              // UpdateBehavior: re-read zones.json when the menu saved it
Zone get(Key k, const char* part = nullptr);               // the zone in force for the gun in hand ("bolt" / "slide" / "pump" for PART)
float radius(Key k, const char* part = nullptr);
// the zone's centre in the world: its anchor (a joint's world position) moved by the offset in the gun's own axes
Vec3 center(Key k, const Vec3& anchor, const char* part = nullptr);
bool gun_rot(Quat& q);                                     // the gun transform's world turn (false = no gun)
void publish(Key k, const Vec3& center, float r, float on = 1.0f);   // for the menu's spheres, this frame
void clear(Key k);                                         // not shown this frame

} // namespace vn::zones
