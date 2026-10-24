# 2026-10-24 (midday): first wear of the handgun build, and what it showed

`/ms` on the home PC, Tefa in the headset, Claude on Opus. Build `6ce3b84` worn, then build 2 of the day installed.

## What Tefa saw (12:00-12:04 run)

- The left hand still sticks to every gun by being near it; LG sometimes snaps the hand onto the gun from any distance.
- When LG docks smoothly, one frame right after the press already shows the hand docked, then the smooth move carries on.
- LG still makes Andyalpa's finger gestures (point / fist). Tefa: they serve no purpose in this game; automatic hand poses
  when picking things up will be worked out instead.
- The handgun's magazine now drops out whole `[reported 2026-10-24]`.
- Racking works as before; on the slide (LEMI) and the pump (M1897) the gun goes through the left WRIST, not the palm.
  The rifle looked fine. Tefa: the left hand must follow all four bolt moves (up, back, forward, down).
- The aim clicks were not tried: Tefa took them out on purpose for the scope.

## What the log showed

- `left hand docks on the gun only with LG held: not available (not the patched REFramework)`. The patched loader with
  `re8vr.grip_needs_button` has not been installed since the scope's 2026-10-01 move to stock REFramework; the rule lives
  in the scope's grip script (`re8_vrz_begone_grip.lua`, BeG0nE repo), and it has been OFF by default since 2026-10-02
  (Tefa wanted auto-dock back for the scope) `[measured 2026-10-24]`.
- `grip taken #N (our own dock on the frozen socket, 0.4 s after letting go)` with the hand 21-74 cm away: that script took
  the grip on the button alone, at any distance, within 3 s of letting go. That is the "snaps from any distance".
- `grip taken #3 (praydog docked ...)` with `button=false`: the 10 cm proximity dock.
- No `heard id` lines at all: the listener watched `WwiseContainer.trigger*`, but the scope's 2026-09-27 recon says the weapon
  clicks come from `app.WwiseWeaponMotionSequence.weaponTrigger / manualTrigger` (21xx ready = fainter, 23xx lowered = louder).
- Shotgun: `HAND ON` then `furthest pull 0.000 m`: LT was not held, so the pump never moved (LT held is now required).

## Build 2 (installed 12:28, not worn)

1. The bridge switches the scope script's own `grip button 1` on (LG only).
2. `re8_vrz_begone_grip.lua`: a take needs the hand near the socket (10 cm), button or not. This also changes the scope mod.
3. Smoothing eases ANY jump of the hand target (over 4 cm in a frame, or a different ask between two solves of one frame),
   not only a change of who places the hand; the scope script docks in a later solve of the same frame, which was the flash.
4. Slide and pump: the hand is moved back by the wrist-to-palm offset (`L_Hand` → `L_Palm`, measured live after the solves,
   only when the wrist reached its target), so the palm sits on the part. Not on the bolt.
5. Bolt: the hand turns with the bolt about its own axis, so it follows up and down as well as back and forward.
6. Sounds: `weaponTrigger` / `manualTrigger` are heard and replayed (newest context of that id, else any; the container
   last). With no job set, the slide / pump / bolt take the removed clicks by themselves once heard: back = a 23xx
   (lowered) click, forward = a 21xx (ready) click. All `[compile-verified 2026-10-24]`.
7. Andyalpa's finger gestures switched off (`re8_vr/re8_hand_gestures.json` `enabled: false`; backup in
   `_backup-2026-10-24-1228-before-visceral-re8-deploy`).

## Read after the next wear

- `left hand docks on the gun only with LG held: true` and `the game docked the left hand without the left grip button -- undone`.
- `smooth: the left hand was asked to jump ...` at each LG press, and no flash.
- `rack: wrist to palm ...` (the offset) and Tefa's word on the palm.
- `job N takes game sound ... by itself` and `handling sound N -> ... played (replayed through ...)`.

## Build 3 (12:35): the game's own handling sounds, every gun

Tefa, 12:30: *"can you just use the normal game sounds for racking, pumping and racking the bolt, i mean all weapons, i was
overthinking it with the rifle disabled sounds"*. So the removed-click picking (21xx / 23xx) is gone again. Each gun now
learns its own sounds from the game's motions as they play: the ids of every fire (24xx) and reload (25xx) motion run are
saved per gun in `visceral_re8/sounds.json` (`learned`), and the handling sounds count from the end of the run: pump back /
forward = the fire run's last two, bolt up / back / forward / down = its last four, the slide going home = the reload run's
last. The handgun's reload is ours, so Experiments has "let the game do its own reload" (`EX_GAME_RELOAD`, 8) for one reload
per gun. `[compile-verified 2026-10-24]`; which ids are which is `[hypothesis]` until heard.

## Second wear (12:49-12:52, build 3) and build 4 (13:07)

Tefa: LG-only works and no far snaps (`the game docked the left hand without the left grip button -- undone` x8). But the
left hand was "super janky": it moved and turned with the gun even when not docked, lagged behind the controller, and turned
by itself when docked. The log: `smooth: the left hand was asked to jump 0.4-0.7 m (between two solves of one frame)` every
frame: the game solves the left arm several times a frame with targets far apart, and build 2's "ease any jump" dragged the
hand between them. Ghost Hand agrees: the left hand wandered up to 52 cm from its usual place `[measured 2026-10-24]`.
Also: the hand went onto the slide as the magazine went in (`HAND ON` at 0.177 m, same millisecond as the insert); the game's
own pump motion no longer plays, but the shell still ejects at the shot; the pouch shells are too small and sit too far from
the fingers (Tefa: lower them about 7 cm for now, then tune with the poser); the bolt "works better and better, hand now moves
with the bolt and looks really good" `[reported 2026-10-24]`; the wrist-to-palm offset measured 2.9 cm.
The weapon-motion "ids" heard were 1 and 2: slots in a motion's sound track, not Wwise ids, so build 3 replayed the walk's
slot 1 as the pump. The pump replay ran (`played (replayed through weaponTrigger)`), but whether it was heard is not known.

Build 4: smoothing back to build 1 (owner change only), plus a later solve within 15 cm of the frame's first answer draws the
first answer (the late dock, the flash); the slide / pump / bolt need a FRESH LG press within 14 cm of the part (was: LG held,
20 cm); the shell sits 7 cm lower in the world; sounds are keyed `<call>:<motion>:<slot>` and replayed only with the context
they were heard with this session (the first learned lists were dropped). `[compile-verified 2026-10-24]`

## Build 5 (13:45): the hand rides the magazine in

Tefa, 13:30: *"LG should go on the slide when held before reaching the activation area and then dock when it's in the area,
just right now it jumps on the slide and the bolt for the rifle straight away unnaturally after inserting the mag ... can we
make the hand stay on the bottom of the mag and follow it fully until it's in the gun, so the LG needs to be released to use
your left hand again, and letting go of LG before the click sound plays that lets the player know that the mag is on now,
just drops the mag?"*

- LG held takes the slide / pump / bolt on entering the 14 cm zone again (build 4's fresh-press rule taken out).
- From the insert until LG is let go, the left IK target holds the magazine: the magazine joint's world pose with the hold
  (`MAG_HOLD`) undone, corrected by the hand joint's measured turn from its IK target. Nothing can take the slide meanwhile.
- LG let go while the magazine is going in (before it seats) drops it (`HAND_FALL`, "LG let go before it clicked in").
- Smoothing knows the magazine as an owner, so the hand eases onto and off it. `[compile-verified 2026-10-24]`

## Third wear (13:49-14:01, build 5) and build 6 (built 14:15, not installed: the game was up)

Tefa: the hand stays on the magazine bottom and letting go before it seats drops it (works); taking the slide closes it at
once (it then has to be pulled back); the hand on the magazine "fights the game at first" (the gun and hands thrown about);
the hand still docks without LG and snaps; pumping makes no sound and the gun jumps for a few frames at the end of the pump;
the pouch shell moves a little with the right controller; on the rifle the left hand leaves the magazine when the controllers
are far apart and comes back when they are close; no handling sound played at all `[reported 2026-10-24]`.
Log: the grip script took the two-handed grip (`button=true praydog_docked=true our_grip=true`) right after an insert; and
the motion-sound UInt32 is 1 or 2 for every motion (2000, 2106, 2305, 2422 ...).

**Found with the REFramework MCP type dump** (the first use of it on this project): the tracks argument of
`WwiseWeaponMotionSequence.weaponTrigger` is an `app.WwiseWeaponTriggerTracks` (kin: `...WithLayersTracks`,
`...WithMaterialTracks`, `WwiseSelectableLayaerTriggerTracks`), from `via.wwise.WwiseTriggerTracks`, with `get_TriggerId()` and
`get_TriggerIdName()`: the game's own Wwise trigger, the same in every run `[inferred-static 2026-10-24]` from the type
database. So sounds are now keyed `wwise:<trigger id>`, saved with their names, and played with `WwiseContainer.trigger(id)`
on the weapon (else the player): learned once, in flat or VR, they play in any later run. This also answers Tefa's idea of
collecting the sounds from the flat-screen game.

Build 6: the late-solve rule draws a later ask that comes back toward the left controller (the grip script's undo of the 10 cm
dock), which build 4/5 had been holding back (why the unwanted dock showed again); `S_GRIP_VETO` (98) = the hand is on the
magazine, read by the grip script through `_G.re8_grip_veto` (no grip, praydog's dock undone); a slide or pump taken where the
game holds it (locked back) stays there; after a hand pump the hand stays on the pump (LT let go before the next).
The rifle's hand leaving the magazine with the controllers far apart is most likely the arm's reach `[hypothesis]`.
`[compile-verified 2026-10-24]`

## The flat sound run (14:20-14:28), driven by the session

Tefa: *"can you run the game and get the sounds you need? they are all on the quick slots"*, then *"please use and update all
the tools we have, even if it doesn't matter for this game and is for data gathering only, to make the tools smarter"*.
Launched flat through `re8drive.py boot` (fixed: it now launches through Steam, the old launch script went with the clean
reinstall), driven with a ViGEm pad (`re-village-scope-vr/dev-archive/tools/re8pad.py`): RT fires from the hip, X reloads,
D-pad = quick slots (up LEMI, right M1897, down F2, left W870). Tefa opened the crafting screen mid-run to make
ammo for the empty reload (correction: the first note blamed the game); a pad press there crafted one handgun ammo stack.
36 named sounds heard. The id is the RE Engine name hash (murmur3_32, UTF-16LE, seed 0xFFFFFFFF) `[verified-numerically
2026-10-24, n=3]`. Picked by timing (`GUN_SOUNDS` in `visceral_re8_sounds.lua`): LEMI slide back RELOAD_C (1.1 s into the
reload), home RELOAD_D + F (1.5 s, together); M1897 pump SHOTGUN_MVT_PUMP (the only after-shot sound); F2 bolt GRAB_LEVER,
PICKUP_I, PICKUP_H, HAND_RELOAD_A. Which is which is `[hypothesis]` until Tefa hears them. Driving facts went to
`ai-game-control-profiles/routes/resident-evil-village/KNOWN.md`; the sound findings to the SoundXfounD board.

## Fourth wear (14:35-14:39): every handling sound "played", none was heard

The log shows each one `played (on the player)` on cue (slide back / home, pump, the four bolt steps), and Tefa heard
nothing, also no magazine sound `[reported 2026-10-24]`. The REFramework MCP type dump of `via.wwise.WwiseContainer`: a
container only knows its own triggers (`exists(UInt32)`, `get_TriggerIdNameList()`), so the player's first container was the
wrong one. Build 7 (not installed yet, the game was up): the learner catches the container the GAME uses while a
weapon-motion sound plays (the weaponTrigger call is under way when the container's trigger runs) with the number it hands
it, and plays through it when that container says it knows the sound; else it makes a fresh `app.WwiseWeaponTriggerTracks`
holding the id and hands it to the player's `WwiseWeaponMotionSequence.weaponTrigger`, the game's own way. New handling
sounds: magazine out (LEMI RELOAD_E, F2 RELOAD_A), magazine in (LEMI RELOAD_B + A, F2 RELOAD_B), shell in (SHOTGUN_SHELL).
`[compile-verified 2026-10-24]`

## Fifth wear (14:47-15:00): the sounds come through

With the container search live (hot-loaded, "Reset scripts"): **every gun's handling sounds play** `[reported 2026-10-24]`.
The log: four containers on the player (`app.WwiseContainerApp`): `pl1000` and one per gun object
(`pl1000/ri3042_Inventory`, `.../ri3036_Inventory`, `.../ri3046_Inventory`); the gun's own one knows its sounds (`exists`
true), the player's does not; none lists names (`get_TriggerIdNameList` empty) `[measured 2026-10-24]`. The made-track route
and the player's container were silent.
Tefa's next asks: a louder click at the back of the slide; the magazine insert makes the left hand dart along the insert and
jump back; the pump's one sound carries both "chhk"s, so split it (back = first half, forward = second); and remove the
game's own after-shot handling (the rifle's bolt and gun turn, the shotgun's shell guard, its sound and the flying shell).
Build 8: the slide back plays RELOAD_C + D, home F; the pump sound is stopped at `pump_split_ms` (220, a guess, in
sounds.json) going back and started from it going forward (`seekTrigger(UInt32, Int32)`); in VR the game's after-shot motion
(24xx) is jumped to its end the moment it plays one of the gun's hand-owned sounds, and that sound is skipped; the smoothing
always draws our own placement in later solves while the hand is on the slide / pump / bolt / magazine. `[compile-verified
2026-10-24]`

## Sixth wear (15:11-15:13) and build 9

Tefa: after a magazine goes in, the left hand goes to a spot and stays while the gun moves freely until LG is let go; the
pump's halves are the wrong way round; the rifle still plays about a second of the game's own after-shot animation before
snapping back `[reported 2026-10-24]`. Log: the shotgun's after-shot motion 2422 was cut at frame 31 of 70 (its first
hand-owned sound), the rifle's after-shot motion is 2400 (not 2422).
Build 9: the magazine's seat and out spot are measured after the solves relative to the right hand's IK target and placed
from that target (the gun transform read before the solve is where the game's animation holds it); the pump halves swapped
(back = second half, forward = first); the after-shot motion (24xx) of a pump / bolt gun is ended by time at frame 8
(`after_shot_cut_frame` in sounds.json) in VR. `[compile-verified 2026-10-24]`

## Seventh wear (15:20-15:28) and build 10

Tefa: gripping the handgun the hand "jumps around a bit like fighting something", flickering many frames going on and off;
walking with the rifle gripped, the hand "jitters a lot around the gripping area"; the shotgun should use the current
push-up half both ways, the push up 10% louder `[reported 2026-10-24]`. Ghost Hand: the game's hand jumped 53 times while the
controller was calm `[measured 2026-10-24]`.
Build 10: the late-solve "toward the controller = an undo, drawn" rule only applies with LG let go (with LG held the grip
script's pulls were drawn every frame); the pump plays its first half both ways, forward at volume 1.1 through
`WwiseContainer.trigger(UInt32, RequestInfo)` with `RequestInfo.set_Volume` (found in the MCP type dump; falls back to the
plain trigger). `[compile-verified 2026-10-24]`

## Eighth wear (15:35-15:40) and build 11

Tefa: the shotgun sound "is really good now"; the hand on the grip still jitters while walking (handgun and rifle); gripping
the handgun and emptying it (the slide locks open) made the hand jump from the grip to the slide; the game ran poorly
(a PC restart usually helps); and the start-up height fault: logos and menus sit low, a recenter brings them up but then
the gun points up when the controller is held naturally `[reported 2026-10-24]`. Log: `grip -> free` then the slide's
`HAND ON` 0.8 s later with LG still held.
Build 11: once the hand has eased onto the grip, its place on the gun is frozen in the gun hand's frame until it lets go (the
walk animation moved the socket); a hand that came from the grip cannot take the slide until LG is let go; the 30
WwiseContainer trigger hooks are off (they ran Lua on every sound in the game and found nothing new). `[compile-verified
2026-10-24]`
