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
