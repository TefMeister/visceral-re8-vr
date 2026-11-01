# 2026-11-01 22:40 to 2026-11-02 01:35 — the Wolfsbane loaded and fanned by hand (/ms, home PC, Tefa in the headset)

Builds b041 to b052 (builds repo, `visceral-re8-vr`). Tefa drove every test; Claude wrote the code between tries.

## What Tefa asked for, in their words

- *"with the wolfsbane magnum revolver ... B to open the reloading cover"*, then the full plan (gate.h holds it verbatim): RT
  shoots; B opens the drum guard; with it open, LG anywhere takes the gun into the left hand (hand at the base of the drum) and
  frees the right hand; RG at the left-hip pouch takes rounds; RG held at the back of the gun docks; RT puts one in; LT turns
  the drum between rounds (a casing falls out, any angle; not before the first); all in, the right hand goes back to the grip
  and the thumb shuts the guard; the left hand stays on the drum until LG is let go.
- *"with the guard closed, LG puts the palm on the hammer and after every shot, LT pushes the hammer down again"*; B while on
  the hammer sends the hand to the drum; then *"can i hold RT and when i press down on the hammer it basically shoots"*.
- *"the drum grab can actually completely go then, as it is not openable at all"*.
- Hand Poser: show the hammer / the right hand's docks as spots; only one hand's sliders at a time; the left hand on the drum
  the same with or without the right hand docked; whole-hand sliders for the right hand too.
- *"left hand is still animating while walking"*, then *"twitching"*; *"both need a subtle finger sway that is not tied to
  movement"*.

## What works now (Tefa's words in the headset)

- The right-hand loading: *"the reload system works and feels awesome!"* `[verified-live 2026-11-01, headset, n=1]`
- The hand poses on the gun, after the shared left hand: *"the hand pose is correct on the weapon now"* `[verified-live 2026-11-02, headset, n=1]`
- The ammo counter as rounds go in: *"the bullets are counting right!"* `[verified-live 2026-11-02, headset, n=1]`
- Fanning with RT held: *"shooting works"* `[verified-live 2026-11-02, headset, n=1]`
- The finger sway: *"hands sway very well on their own"* `[verified-live 2026-11-02, headset, n=1]`

## Still wrong at the end

1. **No muzzle flash on every fan shot**, even with the effects-only request added (b052). The fan shots go off through
   `app.PlayerGun.requestShootForProcess` (log: "asked it with requestShootForProcess" on every one) because the game's own
   held-trigger shot never fires: `WeaponGunCore.readyShootByTimer` reads SHUT in the window (ShootableTime **1.500 s** on the
   Wolfsbane) — our write is undone by the game's own timer update. Next: shorten `ShootableTime` (or reset `ShootableTimer`)
   while the palm is on the hammer, so the game's own shot (with its flash) goes off. `[measured 2026-11-02, n=3 shots]`
2. **With LG on the hammer the game must never cock it**, even with RT let go (Tefa). The right thumb and the hammer joint are
   held by us, but the game's own cocking motion (the drum turning) still plays after a shot.
3. **The guns sit low** on this launch (the 2026-10-29 problem, launch to launch). The gun-place report is on again (it was
   off since the clean rebuild). Bad launch kept: `D:/claude video game stuff/logs/visceral-re8-vr/gunreport-2026-11-02-0132.txt`
   + the full log. Its numbers: the hand 28-38 cm from its IK target, the target only 23-30 cm from the shoulder (arm 55 cm),
   the gun 18-22 cm off the hand `[measured 2026-11-02, n=1 launch]`. A GOOD launch's file is needed to compare.
4. The left-hand twitch: two causes fixed (the game's flickering "gripping" flag; the still pose and the opening hand taking
   turns); Tefa has not worn the second fix yet.

## Found with our own lookup (lookup.cpp, new tonight)

praydog's RE Engine connector cannot run on the installed REFramework (76298bd pd-upscaler build: no .NET; REFramework.NET.dll
logs "exception in reframework_plugin_required_version"; files kept in `D:/RE Village REFramework builds/_connector-tried-2026-11-02`).
So the mod got its own read-only type lookup: questions in `reframework/data/visceral_re8/lookup_ask.txt`, answers in
`lookup_answer.txt` within half a second (see lookup.h). It found, `[verified-live 2026-11-02]`:
- `app.GUIRemainAmmoOrder.updateRemainAmmo(System.Boolean isEnable)` — we had called it with (mode, item); `true` fixed the counter.
- `app.WeaponGunCore`: `readyShootBySequence`, `readyShootByTimer`, `readyShootByTriggerBack`, `ShootableTime`, `ShootableTimer`,
  `setReadyShootBySequence(bool)`, `resetShootableTimer()`; `app.WeaponCore.isKeepHammerMotion`; `app.WeaponSpecialSetting.KeepHammer`.
- `app.PlayerGun.requestShootForProcess(bool)`, `requestShootForProcessEffectOnly()`, `requestShootNoneBullet()`.

## Tools changed

- Hand Poser (hand-poser-vr): the hammer spot; the right hand's spot joined to the left's ("drum + right hand on the cover");
  LEFT HAND / RIGHT HAND show only that hand; the wrist box poses the shown hand (right spots 101 cover, 102 bolt); a spot that
  only adds the right hand shares its left hand with the spot without it.
- build.sh refuses to deploy while re8.exe is still running or closing (b051 was saved during a shutdown and holds b050's files).

## Standing rule added (Tefa)

Every game has a live connector from the start; where none works, making our own is one of the first jobs.
