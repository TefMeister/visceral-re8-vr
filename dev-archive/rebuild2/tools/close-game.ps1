# close-game.ps1 -- rebuild 2: ask Village to close the way its window's X does (WM_CLOSE), then wait until the
# process has really left (about 12 s; KNOWN.md of the route folder). Never ends the process by force.
# Tefa, 2026-11-26 (/ms): "from now on please close the game yourself when you need it closed, i'll still start it".
#   powershell -File close-game.ps1        exit 0 = closed (or was not running), 1 = still there after the wait
$WaitSeconds = 60
$p = Get-Process -Name re8 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $p) { Write-Output "not running"; exit 0 }
if ($p.MainWindowHandle -eq 0) { Write-Output "running but no window to ask; left alone"; exit 1 }
[void]$p.CloseMainWindow()
if ($p.WaitForExit($WaitSeconds * 1000)) { Write-Output "closed"; exit 0 }
Write-Output "asked to close, still running after $WaitSeconds s; left alone"
exit 1
