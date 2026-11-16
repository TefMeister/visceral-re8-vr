# 2026-11-16: b136, the no-game fixes from Tefa's b134 wear (Developer PC, Opus)

Tefa handed the PC over ("pc is all yours!") after reading the b134 list. Built, installed, saved as b136. Not run.
Only the plugin compiled, Lua syntax-checked (`luac -p`) `[compile-verified 2026-11-16]`.

1. **The old magazine flew out of the hand after the spare went in; the hand docked again (items 4 and 5).**
   Cause `[inferred-static]`: at the seat (`reload.cpp`, INSERT -> SEATED) the hand stayed docked on the new magazine
   (`g_hand_on_mag`, the 2026-11-15 "rides in with it" wish), so the old magazine's throw samples were taken at the gun;
   letting go undocked it the same frame and the 0.08 s throw window read the jump from the gun to the controller as a
   throw (capped at 12 m/s). Now: once the spare is seated with the old one in the hand, the hand is free at once
   (`TWOMAG_FREE_AFTER_SEAT`), the throw history is cleared at that moment and at any undock (`throw_reset()`), and the
   two-handed grip is vetoed while the old magazine is held (`handstate.cpp`). Letting go of LG then drops it with the
   hand's real speed only.
2. **Holster spots step too far (item 15).** Our four spots (`visceral_re8_holsters.lua`) keep their own facing and came
   round only past 45 degrees; now 20. Andyalpa's knife, medicine and ammo still follow the player's root, which our
   body turn (`visceral_re8_bodyturn.lua`) brings round past 60 standing / 45 walking / 30 running: those steps are the
   body turn's, so the body turn IS turning the root in the headset (relevant to item 13, "doesn't turn like Leon's").
3. **Ammo pouch size slider (item 15).** The Holster Zones window (holster-zones-vr fa2ed49) has a size slider on the
   AMMO POUCH row, starting at Andyalpa's 24 cm; the game reads it as `__visceral_holster_extra.ammo_left.r` and a
   wrapper on `HJ.tick_ammo_left_zone` (kept in HJ, no new local: the file is at the 200-locals limit) uses it in place
   of his trigger distance for that tick only, release 10 cm further. His saved profile is never changed.
4. **Emporium tabs (item 8).** `LS_CHANGES_TAB = false`: the left stick no longer changes the tab; a short X tap (not
   part of the X + A hold) is Back: inside a tab, the game's own Cancel (back to the three cards); on a page, back to the
   groups; on the cards, nothing (B closes there). ⚠️ Not checked whether the game itself also does something with X in
   the Gunsmithy.
5. **Torch hand sluggish (item 9a).** The left hand off the gun was smoothed at the gun's strength, torch in it or not;
   a left hand holding the torch is now raw (`visceral_re8_hand_smooth.lua`).

Not done, waiting on Tefa: 9b (the beam "flip a bit shakily" — a wobble wanted, or a jump to remove?), 9c (a Hand Poser
line for the torch), 3 (shells slid in with a thumb), 14 (the long-gun block). The builds skip list now has
`*zones_open.json` (the window's own open-row file was counted as a difference).
