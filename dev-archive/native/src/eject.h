// eject.h -- the spent shell / case of a pump or bolt gun leaves when the hand works the pump or bolt, not at the shot
// (board row, 2026-10-24: "the shotgun's shell still flies out at the shot; it belongs to the hand pump"; Tefa the same
// day: "for the shotgun the shell guard opening, sound playing and shell flying out, they have to be removed").
// The game throws it with app.WeaponCore.ejectCartridge() (type_probe.txt; app.PlayerComponent.get_isEjectCartridge is
// the motion event that asks for it) [inferred-static 2026-10-24]. In VR, for a gun the hand cycles, the game's own call is
// skipped, and the same call is made when the hand pulls the pump / bolt fully back, once per shot fired.
#pragma once

namespace vn::eject {

void install();   // first game frame: hook app.WeaponCore.ejectCartridge
void on_shot();   // rack.cpp: a pump / bolt gun fired: a spent case waits in it
void by_hand();   // rack.cpp: the pump / bolt is fully back: throw the waiting case through the game's own call
void reset();     // rack.cpp: the weapon changed

} // namespace vn::eject
