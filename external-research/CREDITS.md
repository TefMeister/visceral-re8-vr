# Credits

Every source this research folder draws on, credited by name. If you should be credited here and are not, or want
something corrected or removed, open an issue on GitHub and we will fix it as soon as we can. We honour requests from
rights holders.

## The game itself

Resident Evil Village (2021) — Capcom. A legitimate copy is needed to use anything here.

## Prior art, tools, and research

| Source / Work | Creator(s) | Link |
| --- | --- | --- |
| REFramework (mod framework, VR support for Village, Lua and plugin APIs) | praydog | https://github.com/praydog/REFramework |
| REFramework nightly builds | praydog | https://github.com/praydog/REFramework-nightly |
| REFramework book (Lua API documentation, `vrmod` page) | cursey and contributors | https://github.com/cursey/reframework-book |
| Universal Lasers (RE4 remake; spawned-mesh sizing) | abarkera4 | https://github.com/abarkera4/Universal-Lasers |
| EMV Engine (RE Engine Lua toolkit) | alphaZomega | https://github.com/alphazolam/EMV-Engine |
| "Hands Off" pack for Village (the reference this port starts from) | Andyalpa | (received privately; see the repository's main CREDITS.md) |

Our own sibling projects this research links to: [re-village-scope-vr](https://github.com/TefMeister/re-village-scope-vr)
(the bullet-spread lever) and [visceral-re2-vr](https://github.com/TefMeister/visceral-re2-vr).

## Missing from this list?

If you, or someone whose work you know, contributed to or inspired anything here and is not credited, please open a
GitHub issue on this repo and we will correct it as soon as possible.

## Sources (2026-11-07)

- **praydog**, REFramework: master commits and nightlies 01434 to 01438, incl. PR #1885 by **wdre9** (HookManager error paths and thread safety) — https://github.com/praydog/REFramework

## Sources (2026-11-11)

- **G4PLS**, REFramework issue #1739 (REFramework.NET "exception in reframework_plugin_required_version"), with comments by
  **danfq** and **UncleSweetshare** (the .NET 10 Desktop Runtime fix) — https://github.com/praydog/REFramework/issues/1739
- **praydog**, REFramework source at `76298bd` and `8c209b1` (`PluginLoader.cpp`, `API.h`, `csharp-api`) — https://github.com/praydog/REFramework
- **cursey and contributors**, the REFramework book's C# API page (requirements) — https://cursey.github.io/reframework-book/api_cs/general/index.html

## Sources (2026-11-14)

- **The Khronos Group**, OpenXR 1.1 reference page for `xrSyncActions` — https://registry.khronos.org/OpenXR/specs/1.1/man/html/xrSyncActions.html
- **praydog**, REFramework source (`OpenXR.cpp`, `VR.cpp`) and nightly 01439, incl. PR #1893 by **Dimcirui** — https://github.com/praydog/REFramework
- **h1nt36r2**, RE2IVR (installer settings) — https://github.com/h1nt36r2/Resident-Evil-2-Remake-VR

## Sources (2026-11-21)

- **PureDark**, REFramework fork with Alternate Frame Warping (RE9_AFW and PRAGMATA_AFW releases, the RE9AFW, RE4RAFW and RE4AFW_CPPVRMod branches) — https://github.com/PureDark/REFramework
- **praydog**, REFramework nightlies 01440 and 01441 (#1895 reported by **Riesu**) — https://github.com/praydog/REFramework

## Sources (2026-11-25)

- **cursey**, kananlib commit 114de171 "Thread: Fix heap lock oversight" (2026-11-17) — https://github.com/cursey/kananlib/commit/114de171
- **praydog**, REFramework "Deps: Update kananlib (fix startup deadlock when freezing threads)" (2026-11-17), nightlies 01441 and 01451 — https://github.com/praydog/REFramework
