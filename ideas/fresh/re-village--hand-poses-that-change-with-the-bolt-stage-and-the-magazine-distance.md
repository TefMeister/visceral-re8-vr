# Hand poses that change with the bolt stage and the magazine distance

Order: 4006
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-10-25

`[raw]` · `[looks doable]` — *the stages and distances are already known to the plugin (2026-10-25); the poses themselves are still to be made*

> "can the hand pose change depending on which stage the rifle bolt racking and mag insertion distance is? for example i would like to grab it with the fingers - the rifle bolt, lift up, pull down, but then change the pose so that the bolt handle sits in the palm and the thumb base and it pushes the bolt back and down like this. with the mag, when inserted for the fingers to grip the pistol handle and the right hand belivably, until LG is let go"

Verbatim record: [`inbox/2026-10-25-re8-hand-poses-per-stage.md`](../inbox/2026-10-25-re8-hand-poses-per-stage.md)

**What it'd take:** one saved finger + wrist pose per gun and stage (bolt: up / back / forward / down; magazine: in hand,
near the well, inserted), made with Hand Poser while Hand Freeze holds the controllers, saved under the plugin's data folder;
the plugin already knows the bolt stage (`rack.cpp` g_bstate / g_turn) and the magazine's distance to the well (`reload.cpp`),
so it blends between the poses as the stage moves and writes them the way `fingers.cpp` does (PrepareRendering post and
BeginRendering pre). "Inserted until LG is let go" = the mag-in pose held while `reload::hand_on_mag()`.
