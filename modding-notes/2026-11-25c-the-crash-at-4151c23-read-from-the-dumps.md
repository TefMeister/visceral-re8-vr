# 2026-11-25c: the crash at re8.exe+0x4151C23, read from the two dumps (/pd, Fable, Build PC)

**The game was not launched. Nothing here was run in the game.** Two crash dumps, the two kept logs and the game's
own code on disk were read. Board rows RE8-077 / RE8-078; FAULTS.md row of 2026-11-25.

## The short answer

1. **What dies is not a GameObject.** It is ONE entry in one of the game's "per-thread request lists"
   (`app.ThreadPoolList<T>`), found already dead when the game empties that list at the end of the frame
   (`app.ThreadPoolMergeExecutor.lateUpdate`). `[inferred-static 2026-11-25, two dumps, identical]`
2. **The lead "our run-time GameObjects (shell2, mag2, magthrow, gl_rounds, the holster markers)" is not supported by
   the dumps.** Destroying a GameObject does not go through this code path at all. `[inferred-static]` It is not
   disproved as a cause of OTHER crashes (the 2026-11-14 one, see below), so the rebuild's object rule stays.
3. **Whose it is: most likely ours, through the ammo counter's keep-right refresh** in `visceral_re8_bridge.lua`
   (three "order" calls every 2.0 s in play since 2026-11-11, each of which makes the game queue a request).
   `[hypothesis]`: it is the only code in the whole install that asks the game for such requests from outside the
   game's own update, the label REFramework put on the list is `app.GUIRequest`, and the same request list is what
   crashed on 2026-10-22 (the ammo counter's `order.show(true)`). **Not proven**: see "What is NOT established".
4. Not the scope mod (its plugin and scripts never touch the game's orders or requests `[measured: grep]`). Not
   REFramework on its own (it queues nothing); but HOW it calls into the game for a script may be part of the
   mechanism.

## The evidence

Dumps: `D:/RE Village REFramework builds/crash dumps/2026-11-25-2011-b175-re8+0x4151c23.dmp` and
`2026-11-25-2215-b178.dmp` (small dumps: thread stacks and registers only, no heap). Tools:
`dev-archive/native/tools/crash/` (new, this session). Text read-outs: `dev-archive/recon/2026-11-25-crash-4151c23/`.

The crashing code, read from `re8.exe` on disk (the file is plain code, not packed) `[measured]`:

```
+0x4151C00  release(obj):                    ; "drop one hold on a managed object"
              if (int)[obj+8] < 0 return     ; a thread-local object: nothing to do
+0x4151C20    rax = [obj]                    ; the object's header
+0x4151C23    rcx = [rax]            <-- CRASH: the header is 0 (b175) / 0xFFFFFFFF0000002C (b178)
              ... --[obj+8]; if it reached 0: destroy and free the object
```

The object's hold count (`[obj+8]`) was still readable and not negative, but its header was gone: **the object had
already been freed (and in b178 its memory reused) while the list still pointed at it.**

The call chain, the same in both dumps (return addresses off the crash thread's stack; names are REFramework's):

| return address | what it is |
| --- | --- |
| +0x41ACF47 | `System.Array.Clear`: for each slot, take the pointer out, `release` it |
| +0xE44565 | `List<T>.Clear` (code shared by every list of objects) |
| +0x20AC336 | `app.ThreadPoolList<T>.merge`: for each per-thread sub-list with entries: copy them into the main list, then `Clear` the sub-list |
| +0x300584E | `app.ThreadPoolMergeExecutor.merge`: calls every registered list's merge |
| +0xA5ABA | `app.ThreadPoolMergeExecutor.lateUpdate` |
| +0x41EA287, +0x414D80A ... | the engine running a script method on a job thread |

Read from the saved registers on the stack `[measured, both dumps]`: the sub-list being cleared was **number 0**, it
held **exactly one entry**, and that one entry was the dead object. (Merge's saved loop counter = 0; `Array.Clear`
was on its first slot with one slot to go.)

REFramework's crash report labels four native functions `via.dti.finalize`; that is its nearest-name guess for code
it has no name for, not a real finalize call. The same goes for `List<KeyValuePair<Type, ActionBase>>.Clear` (shared
list code) and, **importantly, for the `<app.GUIRequest>` in `ThreadPoolList<app.GUIRequest>.merge`: that function is
shared by every `ThreadPoolList` of objects, so the label names ONE of them, not necessarily the one that crashed.**

How the game keeps such objects alive, read at +0x41510E0 (`add_ref`) `[inferred-static]`: a new object starts as
"thread-local" (a negative hold count that is its place in the creating thread's table of locals); the first
`add_ref` takes it out of **the table of whichever thread is running at that moment** and sets the count to 1. The
locals left in a thread's table are freed in bulk later. So an object can die under a list in two ways: one release
too many, or being made on one thread's books and adopted on another's (the first thread then frees it as a leftover).
Which of the two happened here is not established.

## Why the ammo refresh is the suspect

- `visceral_re8_bridge.lua` (the function run at REFramework's `UpdateHID` point, every frame) does this after every
  gun change and **every 2.0 s while a gun is out**: `order:call("cancelHide")`, `order:call("showRemainAmmo", mode,
  item)`, `order:call("updateRemainAmmo", true)` on the counter's `app.GUIRemainAmmoOrder`. Each real one makes the
  game build a request and queue it. Added 2026-11-11 (the "counter shows zero until a shot" fix).
- Nothing else in the install calls a `GUI...Order` in play: praydog's `re8_vr.lua`, Andyalpa's holster scripts, the
  scope mod's scripts and both plugins' sources were searched `[measured: grep 2026-11-25]`. (The Emporium shop
  script does, but only while its shop screen is open.)
- A request queued from a script callback lands in the calling thread's sub-list; "sub-list 0, one entry" fits one
  lone request queued from outside the game's own worker threads.
- History: 2026-10-22 the game crashed in `app.GUIDriver.updateRequestOrder` on a broken `List<app.GUIRequest>` after
  our ammo counter's bad `order.show(true)` calls (note of 2026-10-23). 2026-11-11 the 2-s refresh went in.
  2026-11-14 the first crash of this family, 2026-11-25 two more.

## The 2026-11-14 crash (+0x415879C) and the 2026-11-21 one (+0x49F5794)

+0x415879C is `call [[obj]+0x40]` in a 37-byte helper: a virtual call on an object whose header is bad `[measured:
disassembly]`. Same family in the wide sense (a managed object used after it died), but a different path, and that
one was caught right after a holster marker was made during a load. It may well be a run-time-object fault; today's
two are not. +0x49F5794 (a read of address 0x220) was not looked at.

## CORRECTION, the same night (/lm, flat, the game asked through lookup.cpp) `[measured 2026-11-25, n=1]`

The game has about 100 `app.ThreadPoolList<T>` types, not a handful: among them `app.GUIRequest`, `app.IGUIDriver`,
`app.VibrationTask` (rumble), `app.PhysicsManager.CastRayRequest` / `CastSphereRequest` (ray casts),
`app.DoorRequestOrder`, `app.DoorStateSetManager.DoorStateSetRequestParam`, `app.DoorBehavior`,
`app.InteractRequestOrder`, `app.ItemCore.InstanceWork`, `app.PlayerHealthPointController.HealthPointParam` and
`via.GameObject`. Full list: `dev-archive/recon/2026-11-25-crash-4151c23/threadpool-lists-lookup.txt`. The merge code
is shared by all of them, so **the `<app.GUIRequest>` label says nothing about which list held the dead entry, and the
ammo refresh is ONE suspect among several, no longer the main one.** Back in the frame: our rumble hooks
(`haptics.cpp` on `OrderVibration`), the wall and thrown-magazine ray casts, the door code, and the run-time objects
(a `ThreadPoolList<via.GameObject>` exists). The storm test of the ammo refresh was started (`tools/sim/stormrun.sh`,
`q_storm_gui.lua`: 928 refreshes in about 15 s, no crash) and stopped on Tefa's word: far too short to clear anything.
Point 3 of "The short answer" and "Why the ammo refresh is the suspect" above are to be read with this.

## What is NOT established

- **That the dead entry is a GUI request.** The list type is one of the game's `ThreadPoolList<T>`; which `T` exists
  was not listed (no type dump of Village on disk; the type names are not plain text in the exe).
- **The mechanism** (one release too many, or the cross-thread adoption above), and therefore whether the fault is in
  our call, in how REFramework 76298bd makes it, or a game fault our call only makes likely.
- **That removing the refresh removes the crash.** With about one crash per one to two hours of play, a clean hour by
  luck is likely; an hour without a crash proves little on its own.

## The tests that settle it (each needs the game: FLAT, no headset)

1. **List the lists** (one question through `lookup.cpp` / the eval line): every `app.ThreadPoolList` type the game
   has, and which methods sit at +0x20AC2A0. If `app.GUIRequest` is the only object list, the label is exact.
2. **Crash on demand**: a test switch that runs the refresh EVERY FRAME instead of every 2 s (60 to 90 times the
   rate), on the flat lift save, 10 minutes. A crash at +0x4151C23 within minutes = the cause, measured. No crash in
   10 minutes (about 13 hours' worth of refreshes) = the refresh is cleared and the suspect list widens to every
   script call that makes the game queue something (`requestMotion`, `requestUseItem`, the sound triggers).
3. **The control**: the refresh off (`hud_keep` in off.txt) with everything else as b178, same 10 minutes at the
   normal rate, to make sure the switch itself changes nothing else.

What would show the reading itself is wrong (not just the suspect): a crash at +0x4151C23 with a different chain
above `Array.Clear`, or a sub-list number other than 0. Both are one `crash_read.py` run on the next dump.

## For the rebuild (design note 2026-11-25d)

- The 2-s refresh does not come over. The counter is brought up to date on the events that change it, by the route
  that queues nothing if there is one (`applyToUI` on the driver is the candidate `[hypothesis]`), found in layer 5.
- One rule for every call that makes the game queue or create something: main thread, one fixed point in the frame,
  counted in the log (rule 5 there).
- The run-time-object rule stays (rule 4 there), on the strength of the 2026-11-14 crash, not of today's.
