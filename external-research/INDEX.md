# Research index

**Last `/gr` pass: 2026-10-26 (estate sweep) — FULL.** Folder created this pass. REFramework retakes the standing origin from the head at VR start and on every runtime recenter (the gun-height lead, from source); the accuracy dial already exists in the sibling scope project; public mods size spawned meshes with `set_LocalScale`; from our own files, `ri5052` is the knife Andyalpa's profile remembers. No public Village VR gameplay pack with hand reloads found; REFramework nightly-01433 (2026-10-21) is a Dragon's Dogma 2 fix only.

Status tags: 🆕 new · 👀 being looked at · ✅ used / confirmed · ❌ dead end.

| Date | Topic | Status | Summary |
| --- | --- | --- | --- |
| 2026-10-26 | [REFramework takes the standing origin from the head at VR start, and again on every runtime recenter](topics/2026-10-26-the-standing-origin-is-taken-from-the-head-at-vr-start-and-on-every-recenter.md) | 🆕 | Supports the "gun wrong again" lead; pin the height through `vrmod:set_standing_origin` from the Lua bridge. Pointer in `engine-research/inbox/`. |
| 2026-10-26 | [Accuracy from movement: the lever is already found, in the sibling scope project](topics/2026-10-26-accuracy-from-movement-the-lever-is-already-found-in-the-scope-project.md) | 🆕 | Blend the scattered and clean rotations at the bullet's build step; no spread value needs finding. Pointer in `engine-research/inbox/`. |
| 2026-10-26 | [Drawn spheres ignore their size: public RE Engine mods resize spawned meshes with `set_LocalScale`](topics/2026-10-26-drawn-sphere-size-public-mods-scale-with-set-localscale.md) | 🆕 | Three candidate causes and the read that separates them. Pointer in `engine-research/inbox/`. |
| 2026-10-11 | [A public RE2 VR gameplay pack already does holsters, manual reload and recoil](https://github.com/TefMeister/visceral-re2-vr/blob/main/external-research/topics/2026-10-11-a-public-re2-vr-gameplay-pack-does-holsters-manual-reload-and-recoil.md) (in visceral-re2-vr) | 🆕 | RE2 only; no Village equivalent found on this pass either. |
| 2026-09-29 | [REFramework writes the FOV only on the primary camera, but the eye projection on every camera](https://github.com/TefMeister/re-village-scope-vr/blob/main/external-research/topics/2026-09-29-reframework-writes-fov-only-on-the-primary-camera.md) (in re-village-scope-vr) | 🆕 | Same game, same VR layer; relevant to any extra camera or drawn overlay. |
| 2026-09-11 | [Both 2026-09-10 headset defects are documented REFramework traps, and praydog's own RE8 VR script shows the working shape](https://github.com/TefMeister/visceral-re2-vr/blob/main/external-research/topics/2026-09-11-both-headset-defects-are-documented-reframework-traps.md) (in visceral-re2-vr) | 🆕 | Reads praydog's Village VR script, which this project runs. |
| 2026-08-29 | [Runtime mesh spawning: via.Prefab + instantiate](https://github.com/TefMeister/re-village-scope-vr/blob/main/external-research/topics/2026-08-29-runtime-mesh-spawning-via-prefab-instantiate.md) (in re-village-scope-vr) | 🆕 | Background for the drawn grab-zone spheres. |

## How to add a topic

1. New file in `topics/`, named `YYYY-MM-DD-short-slug.md`.
2. One row added to the table above, newest at the top.
3. Status tags change only here, by the research session; the modding side sends its verdicts through [`inbox/`](inbox/).
