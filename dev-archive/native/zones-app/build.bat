@echo off
rem Builds the Grab Zones window into dist\ (C#, the compiler that ships with Windows' .NET Framework 4), icon beside it.
rem Then `dist\GrabZones.exe --selftest build\selftest` checks the zone file rules without the game, and install.ps1 puts
rem the icon on the desktop. The game half is Visceral RE8 itself (lua\visceral_re8_zones.lua + the plugin), installed by
rem ..\tools\build.sh --deploy.
setlocal
set HERE=%~dp0
if not exist "%HERE%dist" mkdir "%HERE%dist"
if not exist "%HERE%build" mkdir "%HERE%build"
"%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /optimize+ /win32icon:"%HERE%app\grab_zones.ico" ^
   /out:"%HERE%dist\GrabZones.exe" "%HERE%app\*.cs"
if errorlevel 1 (echo APP BUILD FAILED & exit /b 1)
copy /y "%HERE%app\grab_zones.ico" "%HERE%dist\" >nul
echo BUILD OK: %HERE%dist
