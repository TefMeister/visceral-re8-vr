# install.ps1 -- copies Grab Zones from dist\ to %LOCALAPPDATA%\Programs\GrabZones and puts its icon on the desktop.
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-From <folder with the built files>]
param([string]$From = "")
if ($From -eq "") { $From = if (Test-Path (Join-Path $PSScriptRoot "dist\GrabZones.exe")) { Join-Path $PSScriptRoot "dist" } else { $PSScriptRoot } }
$ErrorActionPreference = "Stop"
$to = Join-Path $env:LOCALAPPDATA "Programs\GrabZones"
New-Item -ItemType Directory -Force $to | Out-Null
foreach ($f in "GrabZones.exe", "grab_zones.ico") {
    if (Test-Path (Join-Path $From $f)) { Copy-Item (Join-Path $From $f) (Join-Path $to $f) -Force }
}
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath("Desktop")) "Grab Zones.lnk"))
$lnk.TargetPath = Join-Path $to "GrabZones.exe"
$lnk.WorkingDirectory = $to
$lnk.IconLocation = (Join-Path $to "grab_zones.ico") + ",0"
$lnk.Description = "Move and resize Visceral RE8's grab zones on the gun"
$lnk.Save()
Write-Output "Installed to $to, icon on the desktop."
