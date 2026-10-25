// equipguard.h -- a weapon equip that a SCRIPT forces on the game is let through only for a gun or a knife (2026-10-25, Fable).
//
// Both crashes of 2026-10-25 (13:37:55 and 14:33:47) read the same in the log: a Lua call of app.PlayerWeaponChange.equipWeapon
// threw an access violation inside the game (REFramework caught it), a Lua call of app.EquipController.equipWeapon threw the
// next millisecond, the "weapon in hand" became an inventory item the plugin does not know (ri5003_Inventory, then
// ri5052_Inventory: no joints, no gun transform), and 1.5 s later app.PlayerMotionController.update -> app.WeaponCore.requestMotion
// jumped through that object's type record into .data (re8.exe+0x94676a0, both times) and the game died. The caller is
// Andyalpa's holster script's "finish the stalled native swap" path (re8_vr_holster.lua tick_native_weapon_change_unstick ->
// native_equip -> equipWeapon), whose get_item_weapon hands back ANY app.ItemCore as "the weapon". Neither item was ever in hand
// at any other time today, and no equip exception today was survived [verified-live 2026-10-25, n=2].
//
// Here: the three calls a script uses to put a weapon in the hand (PlayerWeaponChange.equipWeapon, EquipController.equipWeapon,
// EquipController.set_equipWeaponRight) are hooked; when the call returns into REFramework's own module (a Lua call, as
// nodock.cpp tells them apart) and the object is not an app.WeaponCore that is a gun the plugin knows or a knife
// (app.WeaponMeleeCore), the call is skipped and logged with the object's name and type. The game's own calls are never touched.
#pragma once

namespace vn::equipguard {

void install();   // once, after the type database is up

} // namespace vn::equipguard
