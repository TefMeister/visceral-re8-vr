# 2026-11-23 (00:0x, /ms, PC1, Opus): the every-gun check set up, and the dev-guns button

Tefa asked for a weapon-by-weapon VR check (draw + holster, fire, reload by hand, two-handed grip, ammo counter, hand
smoothing on guns only, plus what the board lists as unfinished), one gun at a time, fixing between tries, and for one
save with every gun so the guns need not be given each time. Nothing was tested tonight; Tefa went to bed.

## What was made

- `lua/visceral_re8_dev_guns.lua` (TESTING ONLY, never shipped): REFramework menu node "Visceral RE8: every gun (testing
  only)", button "Give every gun + ammo" (and "Ammo only"). Gives the 16 story guns not already owned and six ammo stacks,
  the way that worked on 2026-10-24 (createItemCore -> get_work -> activeInventory.addItem; ammo by createAndAddItem).
  Item ids = murmur3_32(UTF-16LE "ri<n>", seed 0xFFFFFFFF), recomputed and matching the 10 ids given on 2026-10-24
  `[verified-numerically 2026-11-23]`. GM 79 grenades (1927571624) refused in October, left out. Installed straight into
  `reframework/autorun/` with the game closed; added to `tools/build.sh`'s list so a deploy keeps it. Syntax-checked
  (`luac -p`) `[compile-verified]`; not yet run in the game.
- The save is expected to hold 11 guns already (2026-11-01 note: USM-AI, WCX, Dragoon, Handcannon, Rocket Pistol were
  missing) `[reported]`, so the button should say "5 gun(s) added, 11 already owned, 6 of 6 ammo stacks".
- Saves backed up before: `D:\claude video game stuff\save-backups\village-2026-11-23-before-dev-inventory` (8 files).
  Slot 6 is empty: Tefa saves the all-guns game there.
- Feature IDs RE8-049 (the button and its save) to RE8-067 (one per gun, the knife, the throwables), in
  `claude-memory/feature-ids.md`.

## Next run (the steps printed to Tefa)

1. Load the usual modding save. 2. Insert -> the node -> "Give every gun + ammo"; read the line under it. 3. Look in the
case for the five. 4. Save at a typewriter into slot 6. 5. LEMI first (RE8-050), its six checks plus its board leftovers;
then the rest one gun at a time in the order RE8-051 ... RE8-067. A line Tefa does not mention is NOT passed.
