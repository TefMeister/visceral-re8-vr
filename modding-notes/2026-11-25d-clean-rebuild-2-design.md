# Visceral RE8: the second clean rebuild (design, 2026-11-25, Fable, Build PC)

Step 1 of the plan: the design. **Nothing is built until Tefa has ticked section 4 and answered section 9.** The game
was not launched for this note. Modelled on `visceral-re2-vr/modding-notes/2026-11-07-clean-rebuild-design.md`. The
crash reading it leans on: `2026-11-25c-the-crash-at-4151c23-read-from-the-dumps.md`.

## 1. Why

- 178 builds in six weeks on top of the first rebuild (b001-b017, 2026-10-31): 54 C++ parts (16,100 lines), 25 scripts
  of ours (9,600 lines) beside three of Andyalpa's and praydog's that we changed (18,500 lines), and a game folder
  with 51 scripts in it, 13 of them scope-mod test tools nobody uses `[measured 2026-11-25]`.
- Three faults this month came from HOW the mod touches the game, not from any one feature: joint writes at
  BeginRendering froze other things' drawing (RE8-078, measured); a hook on via.Joint's setters did the same; and the
  crash at +0x4151C23 (twice on 2026-11-25) is a request the game queued for a script and found dead (the 25c note).
  Each was found late because every feature reaches into the game its own way: 12 scripts hook BeginRendering, 10
  hook PrepareRendering, 9 make or delete objects while the game runs.
- REFramework here is the March build (pd-upscaler 76298bd): it has the start-up freeze that upstream fixed on
  2026-11-17, and no .NET, so the live connector cannot run on it.

## 2. Goals, non-goals, anti-goals

Goals
1. Every feature Tefa ticks in section 4 works as it does in b178.
2. ONE way of touching the game (section 5): one place that writes joints, one that makes objects, one that calls the
   game's request systems. A feature asks; it never reaches in itself.
3. Native C++ for everything in play; Lua only where REFramework gives no other way in (section 6 says which).
4. A game folder where every file is put there by one install script from the repo, and nothing else is in it.
5. No crash in an hour of play at every layer, and the crash-on-demand test (25c, test 2) clean.

Non-goals
- New features. Open ideas stay on the ideas page.
- Fixing a feature's known faults while moving it (each keeps its board row).
- RE2 / RE3 / RE4. They take the rule set afterwards, each as its own job.

Anti-goals (a failure even if it compiles)
- Anything Tefa ticked KEEP that stops working.
- A feature carried over with its own private hook, its own joint write or its own object, "just for now".
- An old file copied in whole. The old code is the reference that is read; the new file is written against section 5.
  (Pure sums with no game call in them, such as the recoil curve, the One Euro filter and the zone tests, are carried
  over line by line after a read-through, and said so in the file's header.)

## 3. What is in the game folder today `[measured 2026-11-25, b178]`

| Group | Files |
| --- | --- |
| Ours, native | visceral_re8_native.dll (54 parts) |
| Ours, scripts | visceral_re8_bridge, _menu, _sounds, _holsters, _hud, _origin, _zones, _whitepoint, _bodyturn, _doors, _walls, _hand_smooth, _mag2, _magthrow, _shell2, _gl_rounds, _newgun, _emporium, _emporium_layout, _emporium_shop; re8_vrz_begone_grip; jitterlog |
| Ours, dev only | visceral_re8_dev_guns, _finger_rec, zz_visceral_eval |
| Andyalpa's, changed by us | re8_vr_holster (11,385 lines), re8_vr_holster_visuals (4,156) |
| Andyalpa's, as received | re8_vr_drop_physics, re8_vr_hand_poser |
| praydog's, changed by us | re8_vr.lua (3,015) |
| praydog's package, as shipped | re2_sharpness_removal, re2_smooth_movement, re2_vr_crosshair, re2_vr_grenade, re2_vr_melee, re4_vr_crosshair (all six switch themselves off outside RE2 / RE3 / RE4), utility/, vr/ |
| The scope mod v1.1.5, released files | re_scope_vr.dll; re8_scope_autostart, _m6_mirror_producer, _vr_companion, re8_vrz_reload_guard, _rifle_steady, _scope_sounds_menu, re8scope/ (17 files); 3 rtex files under natives/ |
| The scope mod, test tools | re8_scope_cam_clone, _cam_fix, _cam_probe, _frametime, _harness, _host_follow, _layer_knobs |
| Our apps' in-game halves | hand_poser.lua (+ a stray hand_poser.lua.before-spot22), anim_timing.lua |
| Game root | dinput8.dll (REFramework pd-upscaler 76298bd, 2026-03-11), openxr_loader.dll, PDPerfPlugin.dll + nvngx_dlss.dll (DLSS, off), the controller bindings json, re2_fw_config.txt, 49 kept log files, reframework_crash.dmp |
| data/ | visceral_re8/, re8_vr/, re7_vr/, hand_poser/, anim_timing/, finger_rec/, 20 re_scope_*.txt, 12 flicker-spike pictures |

## 4. Every part: keep, rewrite, drop (Tefa ticks; my proposed verdict first)

KEEP = the feature comes over as Tefa knows it; its code is written fresh to section 5 with the old file as the
reference. REWRITE = it comes over but is built differently, and the line says how. DROP = out of the game folder,
kept in the archive. The layer it lands in is in brackets (section 7).

The plugin's frame (written first, all new)
1. KEEP `plugin.cpp`, `common`, `settings`, `timings`, `json_mini`: start-up, logging, the one table of named numbers, the live-tunable timings, the settings reader [L3]
2. REWRITE `joints.h` into THE joint writer: every feature hands it "this joint, this pose, this frame"; it writes once, at PrepareRendering, in a fixed order, and refuses two writers on one joint (rules 1-3) [L3]
3. REWRITE `bridge` + `visceral_re8_bridge.lua`: controller readings in, rumble out, nothing else. The ammo refresh, the hand-state globals and the jitter-camera call move out of it [L3]
4. KEEP `player`, `weapons`, `handstate`: finding the player and the gun in hand, the weapon table, what each hand is doing [L3]
5. REWRITE `ik` (the one hook on the game's arm solver): reads and changes its own arguments only; no game call, no log line from inside it (rule 8) [L3]
6. NEW the object pool and the request gate (rules 4 and 5): the only code that makes an object or calls a game "order" / "request" [L3]

Recorders and dev tools
7. KEEP `ghosthand`, `jitterlog.lua`, `perfprobe`: Ghost Hand, the jitter recorder, the per-run performance recorder (Lanes rules) [L3]
8. KEEP `gunreport`, `dockreport`: the measuring lines the robot tests read [L6]
9. REWRITE `lookup`, `zz_visceral_eval.lua`, `menukey`: replaced by the REFramework connector if the new REFramework runs it (section 6); otherwise KEEP [L3]
10. KEEP, dev-only install (never in a package) `visceral_re8_dev_guns.lua`, `visceral_re8_finger_rec.lua` [L11]

The body and comfort
11. KEEP `visceral_re8_origin.lua` -> native: standing height right from the start [L4]
12. KEEP `exposure` + `visceral_re8_whitepoint.lua` -> one native part: automatic brightness off, steady light, both eyes the same [L4]
13. KEEP `sleephands`: a sleeping controller's hand drops to the side [L4]
14. KEEP `smooth` + `visceral_re8_hand_smooth.lua` -> one native part: steadier hands, guns only, the left hand eased on and off the gun [L4]
15. KEEP `turn` + `visceral_re8_bodyturn.lua` -> one native part: the body turns like RE2's [L4]
16. DROP `body` (the first body-turn try of 2026-10-24, replaced by `turn` on 10-29; the builder confirms nothing else in it is live before it goes) [L4]
17. KEEP `torch`: the torch you hold [L4]
18. KEEP hip fire with no aim button, no idle pose, the quick slots on thumb rest + right stick, crouch on the right stick held, the menu button tap = map / hold = pause (today inside our re8_vr.lua changes and the bridge) [L4]

Holsters and the HUD
19. REWRITE the four body holster spots: today `visceral_re8_holsters.lua` on top of Andyalpa's 11,385-line `re8_vr_holster.lua`. New: one native part that does only what Tefa uses (the four spots, the draw and put-away, the pouch grabs, the knife, healing by hand). Andyalpa's file does not come over. This is the biggest single piece of the rebuild [L5]
20. REWRITE `re8_vr_holster_visuals.lua` (4,156 lines; makes objects at run time, hooks both render points): the holster markers and the items shown on the body come from the object pool [L5]
21. KEEP `equipguard`: a script-forced equip only for a gun or a knife; a gun in hand is put away, not re-drawn [L5]
22. KEEP `visceral_re8_hud.lua` -> native: the quick-slot cross as four diagonal points [L5]
23. REWRITE `ammo_hud`: the counter at the right hand. No "order" calls and no 2-s refresh (the 25c suspect); brought up to date on a shot, a magazine or round going in, a gun change [L5]
24. KEEP `re8_vr_drop_physics.lua` -> native: dropped items fall, bounce and settle [L5]
25. DROP `re8_vr_hand_poser.lua` (Andyalpa's poser; Hand Poser replaced it) [L5]

The left hand on the gun
26. KEEP `nodock`: the game's own left-hand dock off while LG is up [L6]
27. KEEP `zones` + `visceral_re8_zones.lua`, `whichpart`: the grip zones, the nearest part takes the hand; the tuning sphere comes from the pool [L6]
28. KEEP `dockpose`, Hand Poser's in-game half (`hand_poser.lua`, the app's own file, installed by the app): the wrist and fingers per gun and spot [L6]
29. KEEP `fingers`, `forearm`, `righthand`, `armstretch`: the opening hand, one forearm pose, the relaxed right hand, the rubber arm [L6]
30. KEEP `re8_vrz_begone_grip.lua` -> native: the stacked two-handed grip and the drawn left hand; the W870 steered with both hands [L6]
31. DROP `pairs` (hand pairs, switched off since 2026-10-30) [L6]

Reloads
32. KEEP `reload`, `reload_pose`, `reload_throw`, `reload_internal`: magazines by hand, B drops it, LT / your push seats it, a magazine keeps its own rounds [L7]
33. KEEP `magdisp`: the magazine's look follows its rounds [L7]
34. REWRITE `twomag` + `visceral_re8_mag2.lua`, `visceral_re8_magthrow.lua`: the second magazine and the thrown one are pool objects, made once, never deleted in play [L7]
35. KEEP `rack`, `rack_right`, `pumpbolt`, `eject`: slide, bolt, charging handle and pump by hand, either hand on the bolt, the case leaves on the rack [L7]
36. REWRITE `shells` + `visceral_re8_shell2.lua`: two shells in the hand, the second from the pool [L7]
37. KEEP `shellclip` + the finger-clip tools: the game's own finger movements on our hands [L7]
38. KEEP `re8_vrz_reload_guard.lua` (the scope mod's): a reload is not cancelled by the hands-up block [L2]

The guns that open
39. KEEP `breech`: the revolvers' cylinder and the GM 79's break action, the latch, the hand staying on the barrel [L8]
40. KEEP `gate`, `drumrounds`, `foley`: the Wolfsbane loaded through its cover by the right hand, its rounds visible, its handling clicks quiet [L8]
41. REWRITE `visceral_re8_gl_rounds.lua`: the GM 79's spent shell (our model) and the round bands from the pool; today it makes objects at run time and hooks both render points [L8]

Feel
42. KEEP `recoil`, `haptics`, `dryfire`, `accuracy`: recoil on the hands, the game's rumble, the empty click, handgun accuracy from the hold [L9]
43. KEEP `visceral_re8_sounds.lua` -> native: the slide, pump and bolt sounds, through the request gate [L9]

The world
44. KEEP `walls` + `visceral_re8_walls.lua` -> one native part: hands and the gun stop at walls [L10]
45. KEEP `doors` + `visceral_re8_doors.lua` -> one native part: doors and gates open at the hand [L10]

Options
46. KEEP `visceral_re8_emporium*.lua` (3 files), `visceral_re8_menu.lua`: the VR Options Emporium on the Duke's shop screen. Stays Lua (it is menu code, only alive while the shop is open); its GUI calls go through the request gate's rules [L11]
47. KEEP `visceral_re8_newgun.lua` -> native: the game's "new gun" move shown in VR [L11]
48. KEEP `anim_timing.lua` (the Animation & Timing app's in-game half, installed by the app) [L7]

Other people's files
49. REWRITE praydog's `re8_vr.lua`: start from the file as shipped with the new REFramework, then put back ONLY our changes that a ticked feature needs (the low-hands-at-start fix, hip fire, the torch block, the hand-smoothing entry), each marked with its date. It stays Lua (it is praydog's VR layer) [L1, changes from L4]
50. DROP the six `re2_*` / `re4_*` scripts of praydog's package (they do nothing in Village) [L1]
51. KEEP the scope mod v1.1.5, released files only (the list in section 3) [L2]
52. DROP the scope mod's seven test tools, the stray `hand_poser.lua.before-spot22`, the 49 old logs and the flicker pictures (logs and pictures moved to the work folder, not deleted) [L0]
53. DROP DLSS (`PDPerfPlugin.dll`, `nvngx_dlss.dll`): off for RE games (rule of 2026-10-31) [L0]

## 5. The rule set for touching the game

Each rule names what it rests on. A rule is checked by a script at every build where it can be.

1. **No joint is written at BeginRendering.** Joints are written at PrepareRendering only, after praydog's layer.
   `[measured 2026-11-25, lift test]` Check: `check_begin_joints.py` (exists), now failing the build instead of warning.
2. **No hook on via.Joint's or via.Transform's setters.** `[measured 2026-11-25, n=1-2]`
3. **One writer per joint per frame.** Features hand poses to the joint writer (item 2); it applies them in one fixed,
   written-down order (who runs last is decided in one table, not by load order) and logs a refused double write once.
4. **Nothing is made or deleted while the game plays.** Everything the mod shows (second magazine, thrown magazine,
   second shell, the GM 79's shells and bands, holster markers, the zone sphere) is made ONCE per scene by the object
   pool: on the main thread, after the player exists and no load is running, at one fixed point of the frame. In play
   an object is only shown, hidden and moved. The mod never destroys one; the game does when the scene goes, and the
   pool drops its handles at the scene change before anything can use them. `[rests on the 2026-11-14 crash (an object
   used after it died, right after a marker was made during a load): hypothesis; cheap to obey]`
5. **Anything that makes the game queue or build something (a GUI order, an equip or item request, a motion request,
   a sound trigger) goes through the request gate:** main thread, one fixed point of the frame, never from a render
   callback or a hook on a worker thread, never during a load, at most once per event (no timers that repeat a request
   "to be safe"), counted per kind in the log every minute. `[rests on the 25c reading: inferred-static + hypothesis]`
6. **Every call into the game is checked before it is made** (method found, argument count and kinds), and a call
   that throws twice is switched off and logged once, not retried every frame. `[rests on the 2026-10-22 crash and the
   2026-10-23 flood of 113,905 error lines]`
7. **Holds on the game's objects are paired:** kept across frames = one add_ref, one release, by one owner; nothing is
   released that we did not hold; nothing is kept across a scene change. In Lua, an object made by a script and handed
   to the game is add_ref'd first.
8. **A hook that runs on the game's worker threads only reads and changes its own arguments.** No game call, no
   object, no log line from inside it.
9. **Nothing runs while a save loads or a cutscene owns the player.** One "player ready" flag, read by every feature.
10. **Every feature has its switch in off.txt**, so a fault is halved in two launches.
11. **Per-frame work is native.** Lua in play is praydog's layer, the bridge and the scope mod's own scripts; ours
    hooks nothing at BeginRendering.

## 6. The clean install

1. Save b178 as it stands (section 8), then move the logs, dumps and pictures out of the game folder to the work folder.
2. Take everything of ours and of the mods out: `reframework/`, `dinput8.dll`, `openxr_loader.dll`, the DLSS files,
   the config and bindings files, the three rtex files, anything under `natives/`.
3. Steam's file check ("verify integrity"), until it reports nothing to fix. The music stays muted and the window
   stays 1280x720 (both live in the game's own save and config; checked, set again if the check reset them).
4. REFramework: praydog's current nightly for Village from master, 01441 or newer (it has the start-up freeze fix of
   2026-11-17, the external-research note of 2026-11-25). DLSS stays off, so the pd-upscaler build is not needed.
   ⚠️ Not checked yet, and layer 1 is where it is found out: every finding in the dossier was read on the March
   build; the scope mod's plugin was built against it; whether the nightly's .NET part runs the live connector.
   If the nightly breaks the scope or the VR picture, the fallback is the March build with the rule set (the freeze
   then stays a known REFramework fault).
5. The scope mod v1.1.5 from its released zip, nothing else of its.
6. Only our new code, by one install script that also writes the list of what it installed; the build check compares
   the folder with that list and names any file that is not on it.

## 7a. CHANGED BY TEFA, 2026-11-25 23:0x: FROM ZERO, IN THE ORDER THE GAME IS PLAYED (replaces the layer table below)

Tefa: *"what i want to do now, is really take it from zero. we have the latest build, and we can read it. but what i
want to do, is a complete fresh install, save games and all. and start tackling our mod and what i aim to do as i play
through the game bit by bit. so when i get to the first door, i want to make sure it opens by pushing. when i get lemi,
i want to fully get it done and animated so it works fully, 2 mag reload and all, then the shotgun and so on."*

What that changes:
- **A complete fresh install, saves included** (not only Steam's file check): the game uninstalled, its folder deleted,
  installed again; the saves start from a new game. Everything old is copied away first (section 8; the old saves, the
  lift save and the all-guns save included, kept on D: as test material, not put back into the game).
- **The order is the story's, not the code's.** The base goes in first (REFramework, praydog's VR layer, our frame of
  items 1-7, the comfort set of items 11-18 that is needed from the first minute). After that a feature is built when
  Tefa reaches the thing it is for, and it is FINISHED there, poses and animation included, before he plays on:
  the first door -> doors by push (item 45); the knife; the LEMI -> the hand on the gun, the magazine, the two-magazine
  reload, the rack, recoil, rumble, the click, the counter, its holster spot (the LEMI's share of items 19-37, 42);
  the M1897 -> shells and the pump; then each gun and thing as it comes (the F2 and the scope mod at the castle, the
  Wolfsbane, the GM 79 ...).
- **Section 4 stops being a list to tick up front.** It becomes the catalogue of what exists in b178 to read from;
  whether a part comes over is decided when the game gets there.
- **Section 5 (the rule set) stands unchanged**, and so does "old code is read, not copied".
- **Tefa's tuning** (hand poses, zones, timings, holster spots) is kept aside and brought back gun by gun, checked as
  each gun is done, not poured in at the start.
- **The crash:** with one thing added at a time and played before the next, a crash points at the newest piece. The
  storm tests of RE8-080 stay worth running on b178 before it is taken out, since b178 is where it crashes.
- **My test saves** are copies of Tefa's own saves from this playthrough, taken at each stop (the first door, the LEMI,
  ...), kept in the builds folder; no cheats and no dev guns in his real saves (his rule).

Still to settle before the wipe: question 55 (which REFramework), and the Steam cloud (the old saves come back from it
unless the cloud copy is cleared or the cloud is switched off for Village).

## 7. The layers (as first designed; superseded by 7a)

Each layer: builds; passes the BeginRendering scan and (new) the request / object count check; passes
`tools/sim/lifttest.sh`; its features checked by the robot on the simulator; **then an hour of play with no crash**
before the next layer starts; saved as its own build (a new series, `rebuild 2/v0.2.0-bNNN - Layer N`). One hour proves
little by itself against a crash that came once in an hour or two, so the hours add up: the count that matters is the
total clean hours since layer 3, and the crash-on-demand test (25c) is run again at layers 5 and 9.

| Layer | What goes in | Items |
| --- | --- | --- |
| L0 | The stock game after Steam's check: starts, window, music off | 52, 53 |
| L1 | The new REFramework + praydog's VR layer as shipped: 10 flat starts with no freeze, the lift test, an hour | 49, 50 |
| L2 | The scope mod | 38, 51 |
| L3 | Our frame, no feature: the joint writer, the object pool, the request gate, the bridge, the recorders, the connector | 1-7, 9 |
| L4 | Body and comfort | 11-18 |
| L5 | Holsters, the HUD cross, the ammo counter, dropped items | 19-25 |
| L6 | The left hand on the gun | 8, 26-31 |
| L7 | Reloads: magazines, racks, pump, shells, the finger clips | 32-37, 48 |
| L8 | The guns that open: revolvers, the Wolfsbane, the GM 79 | 39-41 |
| L9 | Feel: recoil, rumble, the click, accuracy, sounds | 42, 43 |
| L10 | Walls and doors | 44, 45 |
| L11 | The Emporium, the new-gun move, the dev tools | 10, 46, 47 |

Who plays the hour is question 3 in section 9. A layer that fails goes back, it is not patched forward.

## 8. b178 stays restorable

- The mod: `builds.py restore visceral-re8-vr 178` (saved; the builds check names one file that changed since,
  `re8_vr_holster.json`, a settings file the game writes: added to the skip list).
- REFramework: the March package is kept (`RE8_pd-upscaler_76298bd_2026-03-11_original-package.zip` in the builds
  folder on D:).
- Before step 2 of section 6, the whole game folder minus the game's own big files (the .pak files, the exe) is
  copied to the builds folder on D: with a checksum list, and that copy is restored once into a spare folder and
  compared, so "restorable" is checked, not assumed.
- Tefa's saves, the hand poses, zones, timings and holster spots (data/) are copied over into the new install as they
  are: they are his tuning, not code.

## 9. Questions for Tefa (numbers carry on from section 4)

54. Item 19: Andyalpa's holster file out, a small native one of ours in. It is the riskiest piece. Yes, or keep his
    file as it is for this rebuild and replace it afterwards?
55. Section 6, step 4: the new REFramework nightly (the freeze fix, maybe the live connector), or stay on the March
    build?
56. The hour per layer: the robot on the simulator (can run while you are away, 12 layers), you in the headset, or the
    robot's hour first and yours on layers 5, 7 and 9 only?
57. Anything in b178 that you use and that is not on the list above? (The list was made from the code, not from
    watching you play.)

## What is NOT established

- Whether every KEEP item works in b178 today: the list comes from the source and the board, and RE8-074 to RE8-078
  are still unworn rows.
- That the rule set removes the crash (25c: the suspect is a hypothesis until the crash-on-demand test).
- That the nightly REFramework runs the scope mod and praydog's layer the way the March build does.
- The size of item 19: Andyalpa's file was not read line by line for this note.
