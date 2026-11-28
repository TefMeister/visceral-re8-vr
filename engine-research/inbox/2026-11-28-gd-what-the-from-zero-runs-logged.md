# Gold Digger, 2026-11-28 (full scan): what the from-zero runs of 2026-11-25 to 11-27 logged

About 1,300 shelved items read (logs, performance, runs, hands, guns, jitter, crashes, menus, other). Most of it
repeats; these are the lines the notes do not mention yet. All `[measured]` from the REFramework log copies on the
shelves, each counted over the unread copies.

1. **Our own plugin asks for three RE2 menu methods that Village does not have**, in 149 runs:
   `body: app.MenuManager.openInventoryMenu not found`, `... closeInventoryMenu not found`,
   `app.GUIInventory.closeInventory not found`. So whatever the body module does at "inventory opened / closed"
   never runs in Village. If the inventory needs it (body hidden or the hands parked while the menu is up), it
   needs Village's own method names; if not, the lookup can be left out for Village so the log stays quiet.
2. **The holster's head hook is missing** in 89 runs: `[re8_vr_holster] share.Startup.updateOnFrameHead hook
   missing; using on_frame defer only`. It falls back, but the holster then runs a step later in the frame.
3. **re-scope-vr's crosshair maths falls back** in 99 runs: `this REFramework does NOT export the mirror's draw
   pose (REF_GetMirrorDrawPose missing)`. The REFramework build in the game folder is not the one with that export.
4. **595 "Failed to load file ... parse error at line 1, column 1" lines**, nearly all `hand_poser\guns/<gun> @ <pose>.json`
   and `any gun @ <pose>.json`, plus `eval_in.json` and `holster_zones_open.json`. That is what REFramework logs
   when `json.load_file` is given a file that is missing or empty: the poser looks up a pose file per gun and
   falls back to "any gun" `[inferred-static]`. Harmless, but it buries real errors: check that the file is there
   before loading it.
5. **Each headset start does one device reset with a refused picture**, in 4 runs (2026-11-26 00:21, 11:28,
   18:51; 2026-11-27 01:24): `on_pre_wait_rendering: timed out`, `Frame not begun when trying to copy`,
   `xrEndFrame failed: XR_ERROR_LAYER_INVALID`, `Attempting to correct invalid layer`, then it carries on and the
   origin is set ("the headset jumped 1.20 m in one frame; view recentered"). Recovered every time; noted so it is
   not chased as a new fault.
6. **One headset jump of 268 m** (2026-11-26 12:26:29): `visceral-re8-origin set (the headset jumped 268.05 m in
   one frame): headset at -222.20 149.39 12.54`. The origin module caught it and recentered. A one-off, n=1.
7. Steady at every start, not ours and known from earlier games: Streamline's `sl.dlss_g.dll`, the
   IntegrityCheckBypass `sussy_*` lines, `OpenVR failed to load`, `FreeCam: Failed to update pointers`.

Proposed board rows (PD): item 1 (Village's own inventory open/close methods, or skip the lookup), item 4 (pose
files checked before loading). Items 2 and 3 only if the holster or the scope crosshair is seen to lag.
