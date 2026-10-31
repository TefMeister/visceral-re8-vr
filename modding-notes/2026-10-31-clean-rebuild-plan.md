# 2026-10-31: the clean rebuild plan (keep only what has proven itself)

Tefa, 2026-10-30 23:1x: *"maybe we have properly installed and uninstalled so many features right now, that it is easier
to uninstall the game and then inspect the mod properly, come up with the superpowers list for a plan for what to keep
and what not to and then rebuild it"*. Tefa, 2026-10-31: *"start a plan we can go through to clear RE8 as it is right now
and rebuild the mod with only features that have proven to work well so far"*.

Why: the game folder holds files nobody installs on purpose, and the night of 2026-10-30 brought faults with no cause
found (the LEMI invisible in the hand, the rifle vanishing and flickering back, the rifle's shadow flickering on Ethan's
back, the scope picture flickering) `[reported 2026-10-30]`.

## Step 1: what is in the game folder today `[measured 2026-10-31]`

`reframework/autorun/` sorted against `dev-archive/native/tools/build.sh`:

| Group | Files |
| --- | --- |
| Ours, installed by build.sh | visceral_re8_bridge, _menu, _sounds, _holsters, _hud, _origin, _zones, _whitepoint; re8_vr.lua (praydog's, our copy with the OpenXR fix); re8_vr_holster, _holster_visuals, _hand_gestures (Andyalpa's, our copies); re8_vrz_begone_grip; jitterlog |
| Ours, test/probe only (build.sh still installs them) | visceral_re8_gun_survey, visceral_re8_gun_cycle, visceral_re8_bodyprobe |
| Ours, NOT in build.sh (put in by hand / by an app) | visceral_re8_emporium.lua (by hand 2026-10-29), hand_poser.lua (the Hand Poser app) |
| Andyalpa's pack, shipped as received | re8_vr_drop_physics, re8_vr_hand_poser |
| The scope mod (and its dev leftovers) | re8_scope_autostart, _cam_clone, _cam_fix, _cam_probe, _frametime, _harness, _host_follow, _layer_knobs, _m6_mirror_producer, _vr_companion; re8_vrz_reload_guard, _rifle_steady, _scope_sounds_menu; re8scope/ (17 files); utility/, vr/ |
| praydog's REFramework package (RE8_pd-upscaler_76298bd zip), NOT strays | re2_sharpness_removal, re2_smooth_movement, re2_vr_crosshair, re2_vr_grenade, re2_vr_melee, re4_vr_crosshair, utility/, vr/ |

`reframework/plugins/`: visceral_re8_native.dll (ours), re_scope_vr.dll (scope mod, trim build 2ac1dd49),
REFramework.NET.dll + Ijwhost + managed/ + source/ (the REFramework MCP's own plugin, auto-installed 2026-10-23).

Game root: dinput8.dll (REFramework), openxr_loader.dll, nvngx_dlss.dll (scope mod's DLSS loader), the controller
bindings file (ours), ModdedByFluffyModManager.txt (Fluffy was used once: check what it put in natives/).
`reframework/data/`: 20 re_scope_*.txt settings, visceral_re8/, re7_vr/, re8_vr/, hand_poser/.

Correction (same day): the six re2_/re4_ scripts were first called strays; they ship in praydog's own package
`[measured 2026-10-31: unzip -l of RE8_pd-upscaler_76298bd_2026-03-11_original-package.zip]`. Every re8_scope_*,
re8_vrz_*, re8scope/ file, the 14 re_scope_*.txt and natives/stm/movie/rtex/*.rtex.5 (3 files) are in the released
RE-Village-VR-Scope-v1.1.5-manual.zip `[measured 2026-10-31]`. Left unexplained: PDPerfPlugin.dll (dated 2026-10-19),
nvngx_dlss.dll; Steam's verify settles both.

## Step 2: every feature, keep or drop (Tefa ticks)

PROVEN = Tefa saw it working in the headset. The list Tefa answers is in the board row and the reply of 2026-10-31.

Proven:
1. praydog's VR base with our cold-start hand fix (re8_vr.lua) `[verified-live 2026-10-30]`: "right from the start! awesome"
2. Steady light, both eyes the same (whitepoint, the 01:10 world look) `[verified-live 2026-10-29]`: "it works!"
3. The scope mod v1.1.5 `[verified-live, many]`; its colour trim (Tefa-tuned) works outdoors, indoors still too dark
4. Magazine out by hand on long guns, LT to seat `[verified-live 2026-10-25]`: "unbelievable", "rifle works"
5. Racking / pump with the left hand, one kept hold per gun, two hands on the pump gun `[verified-live 2026-10-18..25]`
6. The game's own left-hand dock off while LG is up `[verified-live 2026-10-25]`: "no jumps now"
7. Thumb rest + right stick = quick slots `[verified-live 2026-10-25]`
8. Height fix at start (origin script) `[verified-live 2026-10-25]`: "the game height fix worked"
9. Hip fire, no aim button (AIM_OFF), the gun aims right `[verified-live 2026-10-25]`
10. No idle pose (REFramework idle timer set to a day) `[verified-live 2026-10-28]`
11. Andyalpa's holsters, gestures, drop physics, hand poser; recoil / haptics / ammo counter (ported) `[reported]` worn
    since 2026-10-15, never faulted alone; the ammo counter's crash fix of 10-23 is unseen
12. Hand Poser poses per gun `[verified-live 2026-10-18]`: "hand poses and activation areas" (the app is separate)

Built but NOT proven (worn and broken, or never worn):
13. Handgun magazine eject by hand (LG + B): the magazine fell instead of staying in the hand
14. Grip zone spheres: drawn, but "not good enough to rely on"; one crash twice where they are remade
15. Hand pairs (switched off 2026-10-30)
16. Pistol slide from two sides
17. Revolver drum by hand
18. GM 79 grenade insert, the other new gun parts (handle / drum / insert zones)
19. Hand poses per hand spot; the docked-hand mover (Dock Poser in Hand Poser); Gun Poser
20. Body turns like RE2 (turn.cpp)
21. The Emporium options window (only on the monitor; the headset version is Wednesday's Fable job)
22. Empty click on RT (dryfire)
23. Hold-to-keep on the right grip (Tefa already scrapped it 2026-10-30)

Test tools, out of the player build either way (kept in the repo): gun_survey, gun_cycle, bodyprobe, gunreport, the
scope probes. BeG0nE's jitter and Ghost Hand recorders stay in (PROTOCOL 18 / 20).

## Tefa's picks (2026-10-31)

KEEP: 1 2 3 4 5 6 7 8 9 10 11 12 13 14 16 17 18 19 21 22. DROP: 15 (hand pairs), 20 (body turns like RE2), 23 (hold
the grip to keep the gun). Tefa's changes to the kept ones, verbatim in spirit:

- **4** LT seats only the SAME magazine that was taken out and is still held. A NEW magazine from the pouch: LG held and
  brought to the activation area plays the game's own animation of it going into the well (no LT).
- **7** Left thumb on the thumb rest brings up the game's D-pad menu; RG on a weapon icon "takes it out" of the menu.
- **11** No finger gestures (Andyalpa's re8_vr_hand_gestures out). Holster zones set to a default for an adult human.
  The ammo counter shows while RG is held (instead of the game's aim mode, which no button presses any more).
- **19** The docked hand simple and normal: never jumps to the slide when a rack is due; it goes on the slide only with
  LG held in the slide's activation area; the slide can be racked any time, not only when empty; a casing or shell
  flies out only after a real shot, otherwise the rack is cosmetic. Still wanted: the grip-handle dock removed and, on
  handguns, the hand on the bottom of the magazine for the eject / insert; a docked hand's place movable by hand (a hand
  that docks on the rifle's grip handle instead of its magazine is moved to the magazine).
- **22** The game's OWN empty-trigger sound per weapon on every RT press, not our click; a new one only once the last
  has finished, so fast pulls never cut it off and restart it.

## Step 3: clear the game (no game running)

DONE 2026-10-31 ~11:xx: every mod file MOVED (not deleted) to
`D:/RE Village REFramework builds/_before-clean-rebuild-2026-10-31/game/` (366 MB: reframework/, natives/, dinput8,
openxr_loader, nvngx_dlss, PDPerfPlugin, the bindings file, logs, the crash dump, CrashReport_FMMBACKUP.exe; config.ini
left in place, a copy beside); saves copied to `.../saves/1196590/`. Steam verify started. ⚠️ Fluffy Mod Manager still
lists the scope mod as installed: never press its uninstall (it would restore stale backups); reset its list.

1. Back up the whole game folder's mod files, `reframework/data/`, the saves and the system save (music muted there).
2. Remove every mod file; Steam "verify integrity" until the game is vanilla.
3. Start it once flat: it reaches the menu with nothing of ours in.

## Step 4: rebuild in layers, a short headset check after each

1. REFramework + praydog's VR (our fixed re8_vr.lua): picture, hands, height.
2. The scope mod (shipped files only) + steady light.
3. Andyalpa's pack (our copies) + our plugin with only the kept features.
4. Then the kept "not proven" items one at a time, each worn before the next goes in.

build.sh is changed to install exactly the kept list (and nothing that only tests), so a rebuild is one command.

## Step 3 result and layer 1 (2026-10-31, ~09:15)

Steam verify: "1 updated" (CrashReport.exe, which Fluffy had renamed), BuildID 22373341 `[measured 2026-10-31]`, so every
other moved file was ours. PDPerfPlugin.dll (270,848 B, sha 2e3b10d4) + nvngx_dlss.dll (54,779,504 B) are the working
DLSS pair (UpscalerBasePlugin 1.1.2 + DLSS 310.5.3), not game files. The flat menu check was skipped: the files are
proven vanilla and layer 1's first start shows the same.

LAYER 1 INSTALLED: praydog's RE8.zip from the 76298bd package (openvr_api.dll left out, so OpenXR), the DLSS pair, our
re2_fw_config.txt (idle timer 86400, Single Frame Multipass) and our re8_vr.lua (the cold-start hand fix). Nothing else.
Check in the headset: picture in both eyes, hands where the controllers are from the first second, height right.
