# Gold Digger 2026-11-25: the b164 freeze, read against tonight's other runs

From: /gd inside an unattended /fullscan (Build PC, 2026-11-25 ~03:10). Shelves read: logs, crashes, runs,
performance, guns, hands, other (1,229 unread items; most were repeats).

## 1. Only b164 froze tonight [measured 2026-11-25]

- The three earlier runs that end with "Present no longer called" in their log (01:13-01:16, 01:16-01:17,
  01:27-01:33; shelf items `logs/2026-11-25_01-16-23_PC1_re2_framework_log.txt`, `..._01-17-46_...`,
  `..._01-33-39_...`) are **normal quits**: each has "Removing camera (destroyed gameobject)" a few seconds before the
  frames stop, and the run cards say `ended: closed, exit_code 0`. Not freezes.
- The b164 runs are the only two with frames stopping while the game stays open:
  02:34 run (perf csv `perf-2026-11-25-023441`): 72 fps until 02:35:21, 62 -> 31 -> 0 by 02:35:25, right after the
  rifle (`ri3046_Inventory`) was drawn; no "Removing camera" line. 02:43 run (after a PC restart, `perf-...-024353`):
  3 frames, then 0 from 02:43:59. Both times the game process used almost no CPU while stuck (a wait, not a loop).
- The 02:51 run card says `crashed (exit code 0xFFFFFFFF)`: that is the session ending the frozen game, not a crash.
- Board row proposed (OPEN, `GATE: VR USER`): "b162 put back 02:55; launch it once: runs = the freeze is in b163/b164
  (then b163 alone); freezes too = it is older than b163." The FAULTS.md row of 2026-11-25 holds the same.

## 2. A caught access violation in `via.Joint.set_Rotation` at start [measured 2026-11-23, n=1]

`logs/2026-11-23_10-24-38_PC1_re2_framework_log.txt`: at 10:24:32.997, the same millisecond the OpenXR session
became READY and before the headset was active, a Lua call to `via.Joint.set_Rotation` threw (VMContext caught
c0000005, "Invoke threw an exception"). The line before it is `[visceral-re8-zones] the gun in the right hand:
turned 0.0 / 0.0 / 0.0 deg`. REFramework caught it and the run went on. [hypothesis] a script writes a joint before
the body is ready on the first VR frame; worth a guard (skip joint writes until the headset is active). Low.

## 3. Nothing new elsewhere

The other warnings on these shelves are the known start-up ones (the empty settings files, already in the dossier
under "Empty settings files are MISSING files"; FreeCam pointers; Streamline; IntegrityCheckBypass; OpenVR not
loaded; the inventory-menu methods not found). `via.Behavior.reset appears to be calling itself` shows in good and
bad runs alike (b161 has it twice), so it is not the freeze.
