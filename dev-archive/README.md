# dev-archive — Visceral RE8 working source

| Folder | What it holds |
| --- | --- |
| `original-lua/` | Andyalpa's "Hands Off" pack for Resident Evil Village, exactly as received on 2026-10-15 (`MANIFEST.sha256`). The reference for the port; never edited. |
| `native/` | the C++ port: a REFramework plugin (`src/`), the bridge and menu Lua (`lua/`), our copy of praydog's `re8_vr.lua` with stand-down switches, and `tools/build.sh` |

Build: `bash dev-archive/native/tools/build.sh` (Visual Studio 2022 Build Tools, CMake).

The plan and the port order: `modding-notes/2026-10-15-hands-off-port-plan.md`.
