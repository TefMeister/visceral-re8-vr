# Research index

**Last `/gr` pass: 2026-11-28 — CHECK-IN.** Inbox: the /gs correction folded in (the heap-lock fix is not supported as the b164 freeze cause; row now ❌). REFramework quiet: no nightly after 01451 (11-23), no master commits since 11-24, `pd-upscaler` unchanged since 2026-10-11.

_Previous: **Last `/gr` pass: 2026-11-25 — CHECK-IN.** Inbox empty. For the b164 freeze: kananlib (REFramework's helper) fixed a thread-freezing deadlock on the process heap lock on 11-17 (nightly 01441); our `pd-upscaler` 76298bd lacks it. Nightly 01451 (11-23) is a build fix only._

_Previous: **Last `/gr` pass: 2026-11-21 — CHECK-IN.** The Emporium's AFW item: PureDark's frame warping exists for RE Engine in his REFramework fork (RE9, Pragmata, RE4 remake builds) but not for Village, needs DLSS on and uses the numpad; REFramework nightlies 01440 and 01441 (a DD2 exit crash, a start-up deadlock in kananlib) are master only; one topic._

_Previous: **Last `/gr` pass: 2026-11-11 — CHECK-IN.** The connector dead end (dossier §1): the same "exception in reframework_plugin_required_version" line is publicly reported on an ordinary nightly (#1739) and was cured by installing the .NET 10 Desktop Runtime, so it points at the .NET runtime failing to start, not at our `76298bd` build; one topic, pointer in `engine-research/inbox/` and in visceral-re2-vr's (same build). REFramework otherwise quiet since 11-07 (no nightly after 01438, `pd-upscaler` unchanged since 2026-10-11)._

_Previous: **Last `/gr` pass: 2026-11-01 (estate sweep) — CHECK-IN.** REFramework check: master fixed hooks on methods with out/ref float arguments (#1853, 2026-11-01) and made Lua json.dump_file atomic (#1795); the pd-upscaler branch has neither. Library inbox has the hook note._

_Previous: **Last `/gr` pass: 2026-10-26 (estate sweep) — FULL.** Folder created this pass. REFramework retakes the standing origin from the head at VR start and on every runtime recenter (the gun-height lead, from source); the accuracy dial already exists in the sibling scope project; public mods size spawned meshes with `set_LocalScale`; from our own files, `ri5052` is the knife Andyalpa's profile remembers. No public Village VR gameplay pack with hand reloads found; REFramework nightly-01433 (2026-10-21) is a Dragon's Dogma 2 fix only._

Status tags: 🆕 new · 👀 being looked at · ✅ used / confirmed · ❌ dead end.

| Date | Topic | Status | Summary |
| --- | --- | --- | --- |
| 2026-11-25 | [A thread-freezing deadlock fixed in REFramework's helper library (11-17), not in our build](topics/2026-11-25-kananlib-heap-lock-fix-startup-hang.md) | ❌ | For the b164 freeze: a frozen thread holding the heap lock hangs the next allocation; our March build predates the fix. **Not supported by the freeze logs** (every frozen thread was resumed, /gs 2026-11-25); the upstream fix stays a fact. |
| 2026-11-21 | [PureDark's frame warping (AFW) exists for RE Engine, in his REFramework fork, but not for Village](topics/2026-11-21-puredarks-afw-exists-for-re-engine-but-not-for-village.md) | 🆕 | For the Emporium's AFW item: pre-release builds for RE9 (beta.6, 2026-07-09) and Pragmata, an RE4 remake branch, nothing for RE8; needs DLSS or DLAA on, about 500 MB more video memory, debug keys on the numpad; PureDark's add-on, his permission. Keep the item hidden; ask him if wanted. |
| 2026-11-14 | ["Failed to sync actions: XR_SESSION_NOT_FOCUSED" is REFramework logging a focus change, not a fault](topics/2026-11-14-failed-to-sync-actions-session-not-focused-is-a-focus-change-not-a-fault.md) | 🆕 | A success code from the OpenXR spec, logged as an error; all controller input reads inactive while unfocused. A few lines = harmless; a line every frame = worth a note. Same for RE2 and RE3. |
| 2026-11-11 | [The connector's "exception in reframework_plugin_required_version" is the .NET runtime failing to start, not the build](topics/2026-11-11-the-dotnet-connector-error-is-a-runtime-start-failure-not-the-build.md) | 🆕 | Same line on nightly 01371 in Pragmata (#1739), fixed there by the .NET 10 Desktop Runtime; the failing function only writes 1.15.0, so the throw is the mixed managed DLL starting .NET. Check `dotnet --list-runtimes` and the zip's files before calling the connector dead on `76298bd`. Pointer in `engine-research/inbox/`. |
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
