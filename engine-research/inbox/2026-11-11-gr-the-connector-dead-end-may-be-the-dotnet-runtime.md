# The connector dead end may be the .NET runtime, not the 76298bd build

From: `/gr`, 2026-11-11. Dossier section: **§1 The REFramework build in use** and **Dead ends** ("praydog's connector on the
76298bd build (§1)").

Dead end as written: *"No .NET support: praydog's RE Engine MCP (REFramework.NET.dll) logs "exception in
reframework_plugin_required_version" and never starts `[verified-live 2026-11-02, n=1]`."*

Found: the same log line is reported on an ordinary REFramework nightly (01371, Pragmata, issue #1739) and was cured there by
installing the .NET 10 Desktop Runtime `[reported]`; the function named in the line only writes the version 1.15.0 (the same
at `76298bd` and `8c209b1`), so the throw is the mixed managed DLL failing to start .NET `[inferred-static 2026-11-11]`.
Topic: `external-research/topics/2026-11-11-the-dotnet-connector-error-is-a-runtime-start-failure-not-the-build.md`.

Suggested change: reword §1 from "no .NET support" to "REFramework.NET failed to start .NET (cause not yet separated)", and
keep the dead end open until `dotnet --list-runtimes` on the home PC shows `Microsoft.WindowsDesktop.App 10.x` and the
files beside `REFramework.NET.dll` match the zip. Low priority: `tools/sim/rv.py` already covers most of the connector's job.
