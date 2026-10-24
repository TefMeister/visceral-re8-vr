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
