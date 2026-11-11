# The connector's "exception in reframework_plugin_required_version" is the .NET runtime failing to start, not the build

**Why it matters here:** the dossier (§1, and its Dead ends) records praydog's RE Engine MCP connector as unusable on
our REFramework `76298bd` (the `pd-upscaler` DLSS build): `REFramework.NET.dll` logs *"has an exception in
reframework_plugin_required_version, skipping..."* and never starts `[verified-live 2026-11-02, n=1]`, read at the time
as "no .NET support on this build". Public sources and REFramework's own source point at a different cause, one that
can be checked on the home PC without swapping the game's `dinput8.dll`.

## What the sources say

1. **The same error on an ordinary nightly, in another game.** REFramework issue #1739 (G4PLS, 2026-04-26, open):
   *"REFramework.NET has an exception in reframework_plugin_required_version, skipping..."* in Pragmata under Linux, on
   **REF Nightly 01371** (a regular nightly with .NET support, not a `pd-upscaler` build) `[reported]`. danfq hit it too
   (2026-07-25). **UncleSweetshare (2026-08-02)** had it in Street Fighter 6 and fixed it: the Wine prefix had an
   incompatible .NET runtime; installing the **.NET 10.0 Desktop Runtime** into the prefix made it load `[reported]`.
2. **What the failing function does.** In `csharp-api/REFrameworkNET/Plugin.cpp` (REFramework, `8c209b1`, the commit our
   `csharp-api.zip` came from) `reframework_plugin_required_version` only writes three version numbers (1.15.0). The
   loader (`src/mods/PluginLoader.cpp` at `76298bd`) calls it inside `try { } catch(...)` and prints exactly our line when
   anything throws. Writing three numbers cannot throw; but this DLL is mixed managed/native code (the file opens with
   `#pragma managed`; the project is built with `COMMON_LANGUAGE_RUNTIME = "netcore"`), so its FIRST call in is where
   the .NET runtime is started. So the line means "the .NET runtime could not be started for this DLL"
   `[inferred-static 2026-11-11, from the source]`.
3. **The version numbers match.** `76298bd` and `8c209b1` both declare plugin API **1.15.0** in
   `include/reframework/API.h`, and `csharp-api` targets **`net10.0-windows`** at both commits `[inferred-static
   2026-11-11]`. A missing REFramework export would have failed when the DLL was loaded, one step earlier, not inside
   this call `[inferred-static]`.
4. **The requirement, from the REFramework book's C# page (cursey):** the *".NET 10.0 runtime installed on your
   system"*, a nightly with .NET support, and `csharp-api.zip` extracted into the game folder `[reported]`.

## What it unlocks

The connector dead end may not be one. Three possibilities, and what separates them (all on the home PC, no game):

- **The .NET 10 runtime that `net10.0-windows` needs is not there for the game** (the #1739 cause): `dotnet
  --list-runtimes` must list both `Microsoft.NETCore.App 10.x` and `Microsoft.WindowsDesktop.App 10.x`. The SDK was
  installed 2026-10-23; whether it put the Desktop runtime where the game looks is the thing to check.
- **The files beside `REFramework.NET.dll` are incomplete or mismatched** (`Ijwhost.dll`, the runtime config file, the
  `managed/dependencies/` folder from the same zip): compare against the `csharp-api.zip` file list.
- **Something specific to `76298bd`** (what the dossier assumed): only left once the first two are ruled out.

If the first or second is it, the connector runs on the DLSS build with no change to the game's VR base. Its job is
partly covered already by the 2026-11-10 live question line (`tools/sim/rv.py`), so this is a convenience, not a blocker.

## Sources

- <https://github.com/praydog/REFramework/issues/1739> (G4PLS; comments by danfq and UncleSweetshare)
- <https://github.com/praydog/REFramework/blob/8c209b1/csharp-api/REFrameworkNET/Plugin.cpp> (praydog)
- <https://github.com/praydog/REFramework/blob/76298bd/src/mods/PluginLoader.cpp> (praydog)
- <https://github.com/praydog/REFramework/blob/76298bd/include/reframework/API.h> (praydog)
- <https://cursey.github.io/reframework-book/api_cs/general/index.html> (cursey, the REFramework book)
