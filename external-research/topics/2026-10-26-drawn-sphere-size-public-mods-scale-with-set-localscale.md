# Drawn spheres ignore their size: public RE Engine mods resize spawned meshes with `set_LocalScale`

**Date:** 2026-10-26 (`/gr`, FULL pass) · **Status:** 🆕 new · **For:** the `[PD]` row "THE DRAWN SPHERES IGNORE THEIR
SIZE" (`set_Scale` on the sphere's transform does not change what is drawn; `[hypothesis: the axis material draws at a
fixed size, or the bounds are stale]`).

## What public, working mods do

`[reported 2026-10-26]`, read in GitHub's viewer:

- **Universal Lasers** (abarkera4, Resident Evil 4 remake, REFramework Lua) spawns two GameObjects with a mesh each (a
  beam and a dot), **parents each one to the gun's transform**, and every frame sets world position and rotation and
  then the size through **`set_LocalScale`** (the beam stretched along its length to the hit distance, the dot grown
  with distance). It is a released, working mod, so on RE Engine a spawned mesh does follow a per-frame
  `set_LocalScale`.
- **EMV Engine** (alphaZomega) and the community trainers built on it also use `set_LocalScale` on spawned objects'
  transforms.
- **Andyalpa's own holster visuals** (in this repo, `dev-archive/original-lua/autorun/re8_vr_holster_visuals.lua`) use
  both: `set_Scale` on some world-placed probes and `set_LocalScale` on transforms placed with `set_LocalPosition`.

Our zones script (`visceral_re8_zones.lua`) draws each ball as an unparented GameObject and sizes it with
`set_Scale` only.

## Three candidate causes, and the read that separates them (`[hypothesis]` each)

1. **Wrong setter for this object.** Try `set_LocalScale` with the same number (for an unparented object, local and
   world should agree); read back both `get_Scale` and `get_LocalScale` the next frame. If the read-back holds the new
   number and the drawn size still does not change, the setter is not the problem.
2. **A skinned mesh.** If the sphere mesh (or the "gun copy" fallback, which reuses the gun's own mesh) has a skeleton,
   what is drawn may follow its joints rather than the GameObject's scale `[hypothesis]`. Read the mesh component's
   joint count, or scale the root joint instead, and compare.
3. **The material, as the board suspects.** The "axis" look may draw at a fixed screen or world size. Swap to a plain
   material for one run with everything else equal: if the size follows the number then, it is the material.

The board's own 22:06 crash (a remade sphere's `setMesh` throwing inside the game) argues for reading first and
remaking nothing until one of the three is ruled in.

## Sources

- abarkera4, **Universal Lasers** (RE4 remake) — <https://github.com/abarkera4/Universal-Lasers>
- alphaZomega, **EMV Engine** — <https://github.com/alphazolam/EMV-Engine>
- praydog, **REFramework** (Lua API: `create_resource`, transforms) — <https://github.com/praydog/REFramework>

No code was copied; the approach is described in our own words.
