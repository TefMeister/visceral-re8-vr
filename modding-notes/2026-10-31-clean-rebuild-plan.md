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
| STRAYS: other games' scripts, nobody installed them on purpose | re2_sharpness_removal, re2_smooth_movement, re2_vr_crosshair, re2_vr_grenade, re2_vr_melee, re4_vr_crosshair |

`reframework/plugins/`: visceral_re8_native.dll (ours), re_scope_vr.dll (scope mod, trim build 2ac1dd49),
REFramework.NET.dll + Ijwhost + managed/ + source/ (the REFramework MCP's own plugin, auto-installed 2026-10-23).

Game root: dinput8.dll (REFramework), openxr_loader.dll, nvngx_dlss.dll (scope mod's DLSS loader), the controller
bindings file (ours), ModdedByFluffyModManager.txt (Fluffy was used once: check what it put in natives/).
`reframework/data/`: 20 re_scope_*.txt settings, visceral_re8/, re7_vr/, re8_vr/, hand_poser/.

Still to sort before step 3: which scope files are the shipped v1.1.5 zip and which are dev leftovers (compare with the
zip), and what Fluffy put in `natives/`.

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

## Step 3: clear the game (no game running)

1. Back up the whole game folder's mod files, `reframework/data/`, the saves and the system save (music muted there).
2. Remove every mod file; Steam "verify integrity" until the game is vanilla.
3. Start it once flat: it reaches the menu with nothing of ours in.

## Step 4: rebuild in layers, a short headset check after each

1. REFramework + praydog's VR (our fixed re8_vr.lua): picture, hands, height.
2. The scope mod (shipped files only) + steady light.
3. Andyalpa's pack (our copies) + our plugin with only the kept features.
4. Then the kept "not proven" items one at a time, each worn before the next goes in.

build.sh is changed to install exactly the kept list (and nothing that only tests), so a rebuild is one command.
