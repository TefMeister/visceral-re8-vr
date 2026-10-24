# 2026-10-24 (evening, second /pd): every gun, without equipping them one by one

Tefa: *"can you do all the other guns in the game as well, or do you need me to equip them one by one?"*
**The game was not launched; nothing here has been run in the game.**

## What each gun needs, and what was already generic

The hand reload, rack, pump, bolt, eject and pouch code is generic: `weapons.cpp` already lists all 27 guns with their
reload style (magazine, single rounds, pump, bolt, break action, revolver), and the moving parts are found by joint name
(`Magazine`, `Slide`, `Bolt`, `Reload_Slider` / `Pump` / `Forend`, `Bullet`). Two things are per gun:

1. **its joint names**, logged so far only for the three guns ever held: LEMI (ri3046), F2 Rifle (ri3042), M1897 (ri3036);
2. **its handling sounds**, mapped by hand in `visceral_re8_sounds.lua` `GUN_SOUNDS` for the same three.

## The sound id is the RE Engine name hash

A Wwise trigger id here is murmur3_32 of the name in UTF-16LE, seed 0xFFFFFFFF `[verified-numerically 2026-10-24, n=39]`
(the usual RE Engine string hash; whether `via.murmur_hash.calc32` gives the same was not checked): every name the game reported (`sounds.json` "names") matches. FNV-1, the usual
Wwise hash, matches none. So a gun's sound ids follow from its sound names, and a name guess can be checked.

## The survey: every owned gun at once

Every owned gun is its own game object under the player (`pl1000/ri3042_Inventory`), each with its own sound container
`[measured 2026-10-24]` (the fifth wear's log). A container will not list its names (`get_TriggerIdNameList` came back
empty) but answers `exists(id)`. New probe `lua/visceral_re8_gun_survey.lua`, installed 17:48:

- 8 s after the player appears, finds every `ri<n>` object under the player (3 deep);
- logs its joints with their parents (also settles the pouch shell's parent);
- asks its container about every name pattern seen so far: 120 actions (RELOAD_A-L, PICKUP_A-L, HAND_RELOAD_*, GRAB_LEVER,
  HAND_MAGAZINE, TAKE_SHELL, MVT_PUMP, ...) for the gun's own `SND_MOT_RI<n>_SE_` and the shared `SND_MOT_RI_SE_<family>_`
  names (families: none, SHOTGUN, HANDGUN, RIFLE, MAGNUM, SNIPER, MACHINEGUN, GRENADE, REVOLVER), 120 asks a frame;
- writes `reframework/data/visceral_re8/gun_survey.json` and one log line per known name.

The hash in the shipped file is tested by `tools/survey_hash_test.sh` (cuts it out between its markers, runs it with a
stand-alone Lua against the 39 pairs in `tools/survey_hash_known.lua`): 39 of 39; with the seed broken on purpose, 0 of 39.

Not established: that the gun objects of guns not in hand are under the player and keep their containers loaded
`[hypothesis]` (seen for the three owned guns at once in one run, so likely). A name the patterns do not cover is missed.

## The catch: the save owns three guns

`weapon_ids.json` has only LEMI, M1897 and F2. The survey can only ask guns the save owns, so the other guns need giving
first: the board's unlock-all row. `app.InventoryManager.createAndAddItem(UInt32, Int32, UInt32, Int32) -> app.ItemCore`
is the likely call `[inferred-static 2026-10-24, type_probe.txt]`; the weapon item ids are not known yet. That is a flat job
Claude can do alone (REFramework MCP: read an owned gun's item id, then give the rest).

## Done now, without the survey

`VARIANT_OF` in the sounds script: the Mercenaries and Shadows of Rose LEMI, F2 and M1897 use their base gun's sounds, and the
W870 TAC uses the M1897's, which are the shared shotgun names `[hypothesis]`. A sound only plays through a container that
knows it, so a wrong guess is silent, not a wrong sound.

## Order from here

1. Flat, Claude alone: give every gun (unlock-all); any load then runs the survey.
2. /pd: map each gun's sounds and joints from `gun_survey.json` into `GUN_SOUNDS` / `weapons.cpp`.
3. Tefa wears each gun's reload; sounds and fit tuned by ear and hand.
