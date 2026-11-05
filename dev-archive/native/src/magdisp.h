// magdisp.h -- the magazine's LOOK follows its own rounds (2026-11-05; Tefa 2026-10-31: "we need to change the mag that goes
// in full from the pouch when the gun is empty, also the mag in hand changes to the empty model when that one last round is
// fired. the empty mag model should only be the one that comes out of the gun when all but one ammo is depleted").
//
// How Village draws a magazine's rounds (app.WeaponGunCore, type_probe.txt 2026-10-31): the gun mesh has parts that VANISH when
// the magazine is empty (`switchVanishEmptyPartsDisp`, a list of part numbers, on when `IsEnableVanishEmptyPartsDisp`) and a
// SECOND magazine part (`SecondMagazinePartsNo`, `IsSecondVanishEmpty` / `IsSecondVanishNoEmpty`), switched by
// `execSwitchVanishEmptyPartsDisp()` from the GUN's own round count. The magazine in the left hand is that same mesh (its
// joint moved to the hand), so a fresh pouch magazine in an empty gun's hand looked empty, and the pulled-out one turned empty
// when the chambered round was fired. Here, while the magazine is out of the gun, those parts follow reload::mag_rounds_out()
// instead, written after the game at the same three points as the magazine joint; when it seats again the game's own switch
// is run once so its look is the game's again. The thrown copy (visceral_re8_magthrow.lua) gets the same facts over the bridge.
#pragma once

namespace vn::magdisp {
void point();   // LateUpdateBehavior post, PrepareRendering post, BeginRendering pre: after reload's joint writes
}
