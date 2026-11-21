# PureDark's frame warping (AFW) exists for RE Engine, in his REFramework fork, but not for Village

**Why it matters here:** the Emporium plan (`modding-notes/2026-11-15-emporium-three-tabs-all-gunsmithy.md`, Graphics
and Display item 2; board row "EMPORIUM RESEARCH ITEMS, WEDNESDAY") lists *"AFW = PureDark's frame warping (not looked
at yet)"*. Until now this estate knew AFW only as PureDark's **UEVR** fork (the Silent Hill 2 work; the cross-engine
library's `docs/runtime-layers/README.md`, "Frame warping as a plug-in"). This pass found that the same AFW also exists
for **RE Engine**, as PureDark's fork of praydog's REFramework. Read online through the GitHub viewer and API only;
nothing downloaded, no code copied.

## What the sources say

1. **Where it lives.** `PureDark/REFramework` is a fork of praydog's REFramework (last push 2026-08-26). Its releases are
   all pre-releases: **`RE9_AFW_v1.0-beta.1` to `beta.6`** (2026-03-29 to 2026-07-09) and **`PRAGMATA_AFW_v1.0-beta.1`**
   (2026-05-19). Branches: `RE9AFW`, `RE4RAFW` (newest commit 2026-08-24), `RE4AFW_CPPVRMod` (2026-08-26),
   `pd-upscaler`, `master` `[reported]`. **No Village (RE8) build or branch** was found `[reported; one listing of
   releases and branches, not a proof that none is planned]`.
2. **What it is** (the beta.6 release notes) `[reported]`: *"Alternate Frame Warping ... a new rendering method that can
   probably boost the performance in VR for about 60-80%"*; it also fixes DLSS "wobbling" in VR, at the cost of a
   volumetrics difference between the eyes (like the old alternate-eye method); about 500 MB more video memory; aim for
   the headset's refresh rate (90, else 72); do not combine with the runtime's own motion smoothing unless the headset
   runs 120 Hz or more. **It needs DLSS or DLAA switched on in the game** (FSR3 works badly; FSR4 suggested). An extra:
   dynamic foveated rendering through quad views, RE9 only.
3. **Its debug keys are the numpad** `[reported]`: keypad 7 (AFW against the normal sequential frames), 9 (UI fix),
   4 (the DLSS wobble fix), 6 (a debug view tinting moving objects), `*` (sharpening), `+` / `-` (sharpness).
4. **How it is built, from the branch comparison** (`pd-upscaler...RE9AFW`: 58 commits ahead, 36 files) `[reported,
   file names only]`: a compiled add-on behind a published header (`dependencies/pd-afwmod/include/PDAFWPlugin.h`, a
   dummy stand-in in the repo), a camera duplicator, an upscale helper and large changes to REFramework's VR, D3D12 and
   OpenXR parts. The RE4 remake branch's first commits (2026-03-21 to 03-24) say: AFW working for RE4R, fixed for
   OpenXR, the volumetrics fixed by putting the old view-projection matrix back before the post-process layer
   `[reported]`. The branch is based on an older `pd-upscaler` than ours (301 commits behind the current one).
5. **Terms:** as for the UEVR AFW (library page), the add-on is PureDark's work, its licence is not established, and it
   is used only with his permission `[reported, as recorded by our Silent Hill 2 work]`.

## What it means here

- **There is nothing to install for Village today.** AFW for RE Engine is a per-game build of a different REFramework
  (RE9, Pragmata, RE4 remake); swapping our `76298bd` `pd-upscaler` build for it would change the framework every one
  of our scripts and the scope run on `[inferred-static]`.
- **It ties to DLSS being ON.** The Emporium decision keeps DLSS an option, off by default; an AFW switch would need
  DLSS or DLAA on whenever it is on `[inferred-static]`.
- **Numpad clash:** if a Village AFW build ever appears, its keypad 4 / 6 / 7 / 9 / `*` / `+` / `-` would collide with
  our numpad hotkeys; check the binds before installing `[inferred-static]`.

## Concrete next step

For the Emporium's AFW item: keep it hidden (the "hidden until it works" rule) and record the verdict "no Village build
exists (2026-11-21)". If Tefa wants it, the route is asking PureDark (a GitHub issue on his fork) whether a Village
build is planned or allowed, not porting it ourselves. Re-check the fork's releases at each `/gr` pass.

## Sources

- PureDark, `REFramework` fork: releases (RE9_AFW beta.1 to beta.6, PRAGMATA_AFW beta.1), branches and the beta.6
  release notes, <https://github.com/PureDark/REFramework/releases> (read 2026-11-21).
- PureDark, branch comparisons `RE9AFW` and `RE4AFW_CPPVRMod` against praydog's `pd-upscaler`, through the GitHub viewer
  (read 2026-11-21).
- praydog, `REFramework`, <https://github.com/praydog/REFramework> (the base of the fork).
- Our own: `flat-to-vr-cross-engine-research/docs/runtime-layers/README.md`, "Frame warping as a plug-in: PureDark's
  AFW" (the UEVR AFW and the Silent Hill 2 findings).
