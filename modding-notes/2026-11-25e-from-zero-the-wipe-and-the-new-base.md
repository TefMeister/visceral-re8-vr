# 2026-11-25e: from zero: the wipe and the new base (/lm, Fable, Build PC)

Tefa, 23:1x: *"ok current one, skip the crash tests, wipe. please also delete the userdata for re2, re3 and re8. i want
to really focus on re8 now and then start from zero with re2, mod things one after another as i progress through the
game with all the builds on the side to look at."* The plan it serves: design note 2026-11-25d, section 7a.

## What was done `[measured 2026-11-25]`

1. **Copied away first**, to `D:/RE Village REFramework builds/full-backup-2026-11-25-b178-before-rebuild-2/`:
   - `game-folder/`: the whole Village folder as it stood with b178, everything except the game's own .pak files
     (846 files, 1.3 GB: the mod, both plugins, every script, data/, the configs, the kept logs, the exe);
   - `steam-userdata/1196590`, `/883710`, `/952060`: the Steam save and settings folders of Village, RE2 and RE3
     (28 files), proven identical to the originals by checksum before anything was deleted;
   - `MANIFEST.sha256` (874 lines) and the old `appmanifest_1196590.acf`.
   The mod itself is also build 178 in the builds store (`builds.py restore visceral-re8-vr 178`), and the March
   REFramework package is still in the builds folder.
2. **Deleted** the Steam userdata folders of Village (1196590), RE2 (883710) and RE3 (952060). Steam cloud was
   already off for all three (`cloudenabled 0`), so nothing comes back from the cloud.
3. **Village's folder emptied** of everything but the game's .pak data files (the 14 `re_chunk_000.pak*` and the two
   DLC paks), then **Steam's file check** (`steam://validate/1196590`): it downloaded 130 MB and put back only the
   game's own files (the exe, its DLLs, `config_default.ini`). Not a 35 GB re-download: Steam checks every data file
   against its own list, so the result is the same files as a new install. (A literal uninstall and download is one
   word from Tefa if he wants it.)
4. **The new base**, and nothing else: praydog's REFramework nightly 01451 (2026-11-23, commit 22c713ce; the build
   after the start-up freeze fix of 11-17), from `REFramework.zip` + `VR.zip` of praydog/REFramework-nightly, kept in
   `D:/RE Village REFramework builds/REFramework-nightly-01451-2026-11-23/` with checksums. Installed: `dinput8.dll`,
   `reframework_revision.txt`, `openxr_loader.dll` (not `openvr_api.dll`), `reframework/autorun/re8_vr.lua`,
   `autorun/utility/` (7 files), `autorun/vr/VRControllerManager.lua`. NOT installed: the six `re2_*` / `re4_*`
   scripts (they do nothing in Village), DLSS, the scope mod, anything of ours.
5. **One flat start** (no headset, the simulator not used): REFramework v1.5.9.1+525 loaded, 89 threads frozen and
   89 resumed (no start-up freeze), `re8_vr.lua` ran, the game reached its **Initial Settings** screen (voice
   language, display language, subtitles, audio device): a true first start. Closed by its own close; nothing chosen.
   `[verified-live 2026-11-25, n=1, flat]`

## Seen on the way

- The nightly is ONE `dinput8.dll` for every RE Engine game now (the March package was per game).
- It logs four `[IntegrityCheckBypass] Could not find sussy_...` errors, `FreeCam: Failed to update pointers` three
  times, and one `Failed to get type info`: at start, harmless so far `[hypothesis]`; to be compared with the March
  build's log (in the backup) if anything misbehaves.
- Its menu has a module the March build did not: `ManualFlashlight`. To be read before our own torch is rebuilt.
- The first window was 1920 wide, not 1280x720, and the new `config.ini` has no window lines yet.

## NOT done, on purpose

- The Initial Settings, brightness and the first minutes: Tefa's (a first setup is done with him).
- The 1280x720 window and the music at zero: both lived in files that are gone now; they are set again at the first
  setup (dossier section 4 has the routes) and confirmed by Tefa once.
- No headset start yet on the new REFramework. That is the first thing to see.
- Our own frame (the new plugin, the bridge, the recorders): not started. `build.sh --deploy` in the repo still
  installs the OLD mod: it must not be run against this folder; the new install script replaces it.
- The builds store has no build for this state yet (its "ours" list names the old files); the first build of the
  new series is made with the frame.
- RE2 and RE3: only their saves were deleted. Their game folders still hold their current builds.

## Next

1. Tefa in the headset on the bare base: initial settings, does VR start, hands, height. One short session (/ms).
2. The frame + the comfort set (design items 1-7, 11-18), then play starts; the first door is the first feature.
