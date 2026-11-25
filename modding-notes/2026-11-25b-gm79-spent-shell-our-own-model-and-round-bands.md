# 2026-11-25 evening (Build PC, /pd, Opus): the GM 79's spent shell is our own model; a coloured band on every round (b171)

Tefa, after b170 (the spent shell was invisible with a live round in the hand: the copy of the gun showed no grenade part):
*"can you copy the shell from the game in blender and have it actually look spent so it's just a shell without the live
front part, and use that in game? i imagine we'd have to do that in RE3 too, and i thought it would be great to have a
coloured band over different ammo types - red is explosive, blue is flash"*. The game was not launched; nothing here has run.

## What the game ships `[measured 2026-11-25]`

- The rounds are PARTS of the launcher's own mesh, `character/it/it02/080/it02_080_grenadelauncher_antique.mesh`, all
  weighted to the `Ammo01` joint: part 9 is the empty case (open at the front, primer at the back, 4 cm across, 5 cm long),
  parts 6 / 7 / 8 the three warhead fronts (gold, bronze, silver with a red line). The pickup models
  (`it03_500_grenadelauncher_normal`, `it03_501_grenadelauncher_flash`) match parts 6 and 7.
- So b170's scan of the gun copy's parts 0-80 should have found part 9; that it did not is still unexplained (the copy's
  `Ammo01` joint may not have been where the scan looked). Not chased: our own model replaces the copy.
- Village has two rounds, explosive and flash (Tefa, checked on the web). Flame, acid and mine are RE2 / RE3 rounds.
- The pak puller (visceral-re2-vr `tools/re-engine/pak_pull.py`) reads Village's paks as they are, with Ekey's
  `RE8_STM_Release.list`; extracted files live in `D:\RE Village REFramework builds\extracted (game data - never commit)\`.

## The look, agreed with Tefa over six renders

The game's own case; the inside scorched (burnt brown at the mouth to soot at the floor); the groove at the base filled by
a flush paint band, a narrow groove left on each side (*"use the coloured bands as a filler for the bases, on both spent
and live shells"*), nothing in the middle; the paint dull and worn like factory paint (*"right now they look like
additions"*). Colours: explosive gold, flash blue, flame red, acid olive green, mine purple. Tefa: *"they look great now!"*

## What was built `[compile-verified 2026-11-25]`, b171, installed, not run

| piece | file |
| --- | --- |
| models | `tools/blender/build_gm79_spent_shell.py` (Blender 5.3 + RE Mesh Editor 0.66) -> `gm79_spent_shell.mesh.2101050001` (case / soot / band submeshes), `gm79_round_band.mesh.2101050001` (the band alone), both in `Ammo01`'s bind frame (the RE2 bracelets' conversion) |
| materials | `tools/mdf_build_gm79_shells.py` -> `gm79_shell_explosive.mdf2.19`, `gm79_shell_flash.mdf2.19`: the launcher's own textures and settings; soot = BaseColor near black; band = BaseColor the round's colour, not metal, its UVs on the base rim's scratched bare metal so the paint looks worn |
| colours, round ids | `data/visceral_re8/shell_bands.json` (both build scripts and the Lua read it; RE2 / RE3 rows go in the same file) |
| plugin | `breech.cpp` writes bridge slots 280-281 (`S_GL_ROUND`): what the gun's `Ammo01` joint shows: 0 nothing, 1 a live round, 2 the spent case. The Lua array is 282 long now |
| Lua | `visceral_re8_gl_rounds.lua`: our spent shell on the joint (the game's own case shrunk to nothing under it), or where the S_SHELL2 slots put it beside a live round in the hand; our band on the live round; the colour from the gun's `getBulletItemID()`, the spent shell keeping the fired round's colour. `visceral_re8_shell2.lua` no longer copies the gun for the GM 79 |
| install | `build.sh --deploy` puts the four files in `natives/stm/visceral/` and switches REFramework's loose-file loader on (config backed up in the deploy backup) |

The meshes and materials are made from the game's files, so they are NOT in git: rebuild with the two scripts (the
commands are in their headers) into `D:\RE Village REFramework builds\gm79-shell-work\build\`, which `build.sh` reads.

Two tool facts found on the way:
- RE Mesh Editor's MDF writer cannot change a file's material COUNT (one material copied to three, or three deep copies,
  wrote files that do not read back); rewriting a three-material Weapon_Default file in place (the M1911's) works. Same
  family as the RE2 bracelets' MDF fault.
- Blender 5.x keeps a copied mesh's vertex-group names on the new object, and RE Mesh Editor then refuses to export without
  an armature: clear `vertex_groups` and the deform layer.

## What one launch answers

FLAT, no gun needed: put `reframework/data/visceral_re8/gl_rounds_test.json` = `{"front": true, "kind": "spent", "type":
"explosive"}` (then `"kind": "band"`, `"type": "flash"`). The log says `MeshResource visceral/gm79_spent_shell.mesh: loaded`
or `NOT FOUND`; the shell floats 35 cm in front of the camera.

| seen | means |
| --- | --- |
| the shell, game-coloured, a gold (blue) band at its base | models and materials load; then the real gun |
| `NOT FOUND` | the loose-file loader is off or the path is wrong (`LooseFileLoader_LogAccessedFiles=true` shows what was asked for) |
| a grey / white / black shell | the material file was not taken: check the `MeshMaterialResource` line |
| nothing, no error | drawn off-camera or in the wrong layer: try `"kind": "band"` too |

Then with the GM 79 (VR): fire, open the barrel: our spent shell sits in the chamber (scorched inside, gold band); pull it
out with a live round in the hand: it is now visible; the live round in the hand and in the barrel shows its band. Load a
flash round: the log prints `the GM 79's bullet item id is N`; put N under `re8.ammo.flash` in `shell_bands.json`.

Not established: whether the band's BaseColor values read as the agreed colours under the game's lighting (tune in
`shell_bands.json`, rebuild the materials); whether shrinking `Ammo01` also hides the warhead when the game shows a live
round there while we draw a spent one (it should not: state 2 is only set when the joint carries the spent case).

## Next

- RE2 and RE3 grenade launchers the same way (Tefa: *"use these shell designs in the other games as well, re2 and re3, not
  re7 for now"*): their own case extracted, the same band and soot; acid and mine and flame colours already in the file.

## 2026-11-25 evening, /lm (Build PC, Opus): the flat test; b172 and b173

The game was driven entirely from behind (window off the screen, pretend pad, pictures from the window itself).

- **b171 drew nothing** `[verified-live 2026-11-25, n=1]`: the mesh file loaded, then `spent: the object took no mesh`.
  `via.render.Mesh.setMesh` takes `via.render.MeshResourceHolder`, `set_Material` takes
  `via.render.MeshMaterialResourceHolder` (read from the running game's type info); the script passed the resource.
- **With holders** (made by hand through the eval script, in play) the spent shell shows: the right size, the game's
  metal, the scorched black mouth, the base rim and grooves; 3 materials ready; the flash file works as well. In the
  factory's dark the band reads only as a faint line (`[hypothesis]` brighter `base_color` values may be wanted: Tefa's call
  in the headset).
- A material file's **first load takes some seconds**, and until it is in, the mesh shows the engine's dark checker pattern.
  On the **title screen** the guns' textures (and even the GM 79's own mesh from the pak) never became ready: such objects
  are tested in play.
- **The flash round's id, measured without a headset**: the GM 79's inventory item lists the rounds it takes
  (`<spec>k__BackingField.Weapon.IncludableItems`): 1927571624 explosive (short name ri2042), **1583016682 flash**; the save
  holds 3 flash rounds. Item ids are the name hash of `ri20xx` short names (table in the game's KNOWN.md).
- **b172** (f36c9c1): `resource()` returns holders; every round colour is loaded once the player is in play; a failed make is
  retried a second later instead of every frame; `shell_bands.json` flash = [1583016682] (copied into the game by hand:
  `build.sh` never overwrites a settings file). Flat `[verified-live 2026-11-25, n=1]`: every mesh and colour file `loaded`,
  `spent: our object made`, `band: our object made`, `the flash band`, no errors.
- **b173**: the test mode shows only the kind asked for (b172 left the spent shell up when switched to `band`).

Not established: the GM 79 itself (fire, open, pull with and without a live round in the hand, the bands on live
rounds): that is headset-hand logic (`breech.cpp`), so it needs VR. The robot tools for it bring the game window to the
front (`vb.py`'s presses, `keys.py`), and equipping the GM 79 in VR goes by number keys, so it was not done from behind.
