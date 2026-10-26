# Accuracy from movement: the lever is already found, in the sibling scope project

**Date:** 2026-10-26 (`/gr`, FULL pass) · **Status:** 🆕 new · **For:** the `[PD]` row "accuracy from movement and the
two-handed grip" (*"find RE8's spread / sway value, then set it from head and hand speed and whether the left hand
holds the gun"*, `MODEL: FABLE`).

## The short version

There is no need to find a spread *value*. Our own `re-village-scope-vr` already traced, in this same game, the step
where each bullet's scatter is decided, and proved a write there controls it `[verified-live 2026-09-21, n=10 shots]`.
That one place is a dial, not just an off switch.

## What the scope project found (Village, same build family)

From `re-village-scope-vr` dossier §9bh–§9bl and the cross-engine library's RE Engine page:

- The gun fires in four steps: use a round → create the bullet from a ray (the exact muzzle axis) → **build the bullet
  from a position and a rotation** → set up the spread from two rotations.
- The game scatters the rotation **inside the create step, before the build step**. The build step is handed the
  scattered rotation (A); the later spread-setup step gets A and the clean aim (B), but the bullet already exists by
  then, so every change made there "measured perfectly and did nothing".
- The working cancel replaces A **at the entry of the build step** with the clean rotation (the shortest-arc turn from
  +Z onto the ray). Five hip shots with 5–12° of scatter each then flew within 0.04°. Measured rifle scatter: 0.005°
  aimed, 8.4° average and 14.9° worst from the hip.
- Traps already paid for: a value-type argument cannot be written from a REFramework Lua hook (reading works), so this
  is a native pre-hook job; in the native pre-hook, argument entries are handles, not pointers, and the argument count
  is not "declared + 2", so validate the data (a rotation must be a unit quaternion).

## How it becomes "accuracy from movement" here (`[hypothesis]`, to build)

At the same entry, instead of replacing A with the clean rotation, **blend** between them: a weight of 0 gives the
clean shot, 1 gives the game's own scatter, and the weight comes from head and hand speed, and drops when the left
hand holds the gun. Because the game picks a fresh scatter direction every shot, a blended weight scales the cone
without inventing any randomness of our own. The scope project's log line (degrees off the clean aim, per shot) is the
measurement to copy, so a run proves the dial moves before anyone judges the feel.

Open for this project: the scope project proved it on the sniper rifle only. Whether every Village gun goes through
the same build step is `[hypothesis]`; check one pistol and one shotgun (the shotgun builds several pellets, so the
blend would run once per pellet).

A public search for a Village no-spread or accuracy mod found none that names these steps `[reported 2026-10-26, one
search]`.

## Links

- Scope dossier, §9bk (the scattered rotation is what the bullet is built with) and §9bl (the fix confirmed):
  <https://github.com/TefMeister/re-village-scope-vr/blob/main/engine-research/ENGINE-DOSSIER.md>
- Cross-engine library, RE Engine page, "Bullet spread is a scattered rotation the bullet is BUILT with":
  <https://github.com/TefMeister/flat-to-vr-cross-engine-research/blob/main/docs/engines/re-engine.md>
- Credit: praydog (REFramework), whose plugin API makes the native pre-hook possible.
