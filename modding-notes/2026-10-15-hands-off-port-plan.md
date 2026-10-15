# 2026-10-15 — Porting Andyalpa's "Hands Off" pack to C++: the plan, and the first piece

## Where this comes from

Andyalpa made "Hands Off", a set of Lua scripts for Resident Evil Village on top of praydog's VR layer, and
does not want to keep modding Village. Tefa asked for it to become **Visceral RE8**, written in C++ the way
`visceral-re2-vr`'s native code is. The pack as received is kept untouched in
`dev-archive/original-lua/` (hashes in `MANIFEST.sha256`).

## What is in the pack

| File | Lines | What it does |
| --- | ---: | --- |
| `re8_vr.lua` | 2,729 | praydog's Village VR layer, with Andyalpa's small edits (arm-IK and heal overrides, a block gesture, a melee nil fix). **Stays Lua.** |
| `re8_vr_holster.lua` | 11,226 | holsters, grabbing items and weapons, medicine, ammo pick-up, per-character profiles |
| `re8_vr_holster_visuals.lua` | 4,144 | the holstered meshes (hip pistol, chest knife, chest medicine) and the glasses-scope overlay |
| `re8_vr_recoil.lua` | 2,215 | physical recoil on the hands (spring, per-weapon intensity) |
| `re8_vr_hand_gestures.lua` | 2,046 | grip / trigger finger poses |
| `re8_vr_drop_physics.lua` | 1,643 | dropped items fall, bounce and settle |
| `re8_vr_ammo_hud.lua` | 1,410 | the ammo counter pinned to the right hand |
| `re8_vr_haptics.lua` | 753 | the game's rumble on the controllers, filtered (**ported, see below**) |
| `re8_vr_hand_poser.lua` | 666 | frozen left-hand finger poses |

About 24,000 lines to port; `re8_vr.lua` is the VR layer itself and keeps running as Lua.

## How it is built

- `dev-archive/native/` — a REFramework plugin, API 1.15 (the DLSS build 76298bd Village runs), same shape as
  RE2's: `plugin.cpp` wires, every feature has its own file, every number lives in `settings.h`.
- **The bridge.** The plugin API gives C++ no VR buttons and no rumble, so `lua/visceral_re8_bridge.lua` copies
  them into a shared float array every frame and fires the rumble the plugin asks for (RE2's proven design).
  Village extra: the bridge also carries the few `re8vr` readings and the globals the not-yet-ported Lua files
  publish. When a file is ported, its slots are filled by the plugin instead and the Lua line goes.
- **The mailbox** (how the array reaches the plugin): RE2 uses a known game method. No Village method list has
  been dumped on our side, so the plugin picks one on its first frame (the first `app.*` `set_` method taking one
  `System.Object`) and names it in `reframework/data/visceral_re8/mailbox.json` for the Lua. `[hypothesis]`
  until a launch logs `BRIDGE ATTACHED`.
- `lua/visceral_re8_menu.lua` — the ported files' menus and saved settings. Each keeps Andyalpa's own saved file
  and keys, so settings made with the Lua pack carry over.
- `lua/re8_vr.lua` — Andyalpa's copy of praydog's script plus our stand-down switches (one per ported feature
  that praydog's code also does). Diff it against `original-lua/autorun/re8_vr.lua` to see every one.

## Port order (each step ships alone; the unported files keep running as Lua)

1. ✅ **haptics** — `src/haptics.cpp` `[compile-verified 2026-10-15]`, not run yet.
2. **recoil** — reads `re8vr` state, hooks the gun's fire; self-contained apart from the hand IK.
3. **ammo HUD** — the GUI pinning; reads the holster's "bare hands" and "weapon id" globals through the bridge.
4. **hand poser + hand gestures** — finger poses. Ghost Hand gets wired in here (lanes PROTOCOL §20).
5. **drop physics**.
6. **holster + holster visuals** — the heart of the pack and a third of its size; split into several files.
   Everything else reads its globals, so until it is ported the bridge relays them.

## Step 1: haptics, what changed and what did not

The game asks the pad to rumble through `app.HIDVibrationManager.OrderVibration` (two overloads). praydog's
script forwarded each order to the controllers; Andyalpa's script swapped the global `vrmod` for a proxy and
filtered those forwards. The plugin now hooks both overloads itself and does praydog's forward and Andyalpa's
filter in one place, then the bridge fires it. Our `re8_vr.lua` stands its own two forwards down while the
plugin says it has them (`__visceral_native_haptics`). The game's pad rumble is never touched.

Kept exactly: the left hand only feels a shot while it supports the gun (docked, or left grip within 32 cm, held
until 48 cm); the strength scale (Low 0.45 / Medium 0.80 / High 1.20, clamped to 1.5); full-auto guns tick
instead of buzzing, each hand once per tick; grab-zone rumble passes unscaled; the master switch
`__vr_reloaded_master_enabled == false` turns the filter off.

Two small differences, both `[inferred-static]`:
- praydog's **melee hit pulses** (`re8_vr.lua` lines ~1856–1863) were also caught by Andyalpa's proxy, because it
  treated every frequency-1 rumble as a shot: the left punch pulse was dropped unless two-handed, and the right
  ones scaled by 0.8. Those calls do not go through the plugin, so they now arrive unfiltered. Watch for it in
  the first headset run; if Tefa wants the old feel back, route them through the bridge.
- praydog's second overload sent the right hand a power-0 rumble when the power was 0; the plugin skips it
  (it did nothing, but it could use up a full-auto tick).

## Install layout: on top of the scope mod v1.1.5 (decided the same evening)

Tefa: *"re8 with scope mod please, so let's just use the 1.1.5 scope mod as a base for our Visceral mod and just
build on top of it."* The Steam install holds exactly the v1.1.5 package (49 files, byte-identical
`[measured 2026-10-15]`), which ships no `re8_vr.lua`, so praydog's stock one runs today. Visceral RE8 adds the
plugin, the bridge and menu Lua, the unported pack files, and our `re8_vr.lua` in place of the stock one.

Before the first launch, three scope scripts get read against the pack, because they touch the same things:
`re8_vrz_reload_guard.lua` (block gesture vs reloads), `re8_vrz_begone_grip.lua` (the grip fixes vs Andyalpa's
arm-IK override and hand gestures) and `re8_vrz_rifle_steady.lua` (vs recoil). Then `build.sh` gets a `--deploy`
that backs up the game folder first; rolling back = the v1.1.5 zip.
