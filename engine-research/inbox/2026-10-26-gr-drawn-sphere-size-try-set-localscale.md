# /gr: drawn spheres ignore their size; public mods size spawned meshes with set_LocalScale

From: `/gr`, 2026-10-26 (estate sweep, FULL pass).

**The board row:** `[PD]` "THE DRAWN SPHERES IGNORE THEIR SIZE" (`set_Scale` on the sphere's transform does not change
what is drawn).

**Lead** `[reported 2026-10-26]`: released RE Engine Lua mods that draw spawned meshes (abarkera4's Universal Lasers for
the RE4 remake; alphaZomega's EMV Engine) parent the object to the gun and size it every frame with `set_LocalScale`;
our zones script uses `set_Scale` on unparented objects. Three candidate causes and the read that separates them
(setter, skinned mesh, material) are in
[`external-research/topics/2026-10-26-drawn-sphere-size-public-mods-scale-with-set-localscale.md`](../../external-research/topics/2026-10-26-drawn-sphere-size-public-mods-scale-with-set-localscale.md).

**Suggested change:** add "read back get_Scale / get_LocalScale, then try set_LocalScale" as the first step of the row,
before any remake of the spheres (remakes crashed at 22:06).
