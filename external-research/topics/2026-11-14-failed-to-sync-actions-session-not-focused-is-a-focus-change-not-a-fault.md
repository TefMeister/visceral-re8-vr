# "[VR] Failed to sync actions: XR_SESSION_NOT_FOCUSED" is REFramework logging a focus change, not a fault

**Status:** 🆕 new · **Priority:** low-medium (explains a log line seen on the RE Engine trio; tells when it matters).

## What is public

1. **The OpenXR specification:** `xrSyncActions` returns `XR_SESSION_NOT_FOCUSED` as a **success code**, not an
   error. The runtime must return it when the session is not focused, and then **every action reads as inactive**
   (no buttons, no sticks, no hand poses from actions) `[reported 2026-11-14, Khronos OpenXR 1.1 reference page]`.
2. **REFramework's OpenXR code** (`src/mods/vr/runtimes/OpenXR.cpp`, master `c38d1fe`): before syncing input it
   checks its own copy of the session state and returns quietly unless that copy says FOCUSED. It then calls
   `xrSyncActions` and logs **any** result other than `XR_SUCCESS` as `[VR] Failed to sync actions: <code>`
   `[inferred-static 2026-11-14]`. Its copy of the state is updated only when it polls the runtime's events.
3. So the line appears when the runtime has already taken focus away (the state-changed event not yet read):
   the headset's system menu or overlay (Quest menu, Virtual Desktop, SteamVR dashboard), another VR app or window
   taking focus, or the headset being taken off or going to sleep `[inferred-static]`. Once REFramework reads the
   event its copy says not focused and it stops calling, so normally only one or a few lines per focus change
   `[inferred-static]`.

## How to read it in our logs

- **A few lines around a menu press, taking the headset off, or a start-up / shut-down:** harmless; input is
  simply paused while the session is not focused `[inferred-static]`.
- **The line repeating every frame for a long stretch** would mean REFramework still thinks it is focused while
  the runtime says not: that would be worth a note (it would show as dead controllers in the game) `[hypothesis]`.
- It is not linked to cutscenes or to our scripts; nothing in REFramework's cutscene handling touches input sync.

## Also checked this pass

- REFramework nightly **01439** (2026-11-12, `c38d1fe`, #1893): clears queued Lua state deletions on "reset
  scripts", so a fresh script state that reuses a freed address is no longer erased the next frame. Relevant only
  to a script reset mid-session (our Lua side); nothing for VR or RE8 `[reported 2026-11-14, commit message]`.
- No public RE Engine VR mod found that shows cutscenes on a flat or virtual screen (RE2/RE3/RE8/RE9; RE2IVR still
  0.8.9 and leaves REFramework's first person off in cutscenes); a negative from three searches plus the two known
  RE2 overhauls' files.

## Sources

- The Khronos Group, OpenXR 1.1 reference, `xrSyncActions` —
  <https://registry.khronos.org/OpenXR/specs/1.1/man/html/xrSyncActions.html>
- praydog and contributors, REFramework source (`OpenXR.cpp`, `VR.cpp`) and nightly 01439 —
  <https://github.com/praydog/REFramework>
- h1nt36r2, RE2IVR (installer settings, releases) — <https://github.com/h1nt36r2/Resident-Evil-2-Remake-VR>
