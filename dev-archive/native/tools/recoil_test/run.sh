#!/usr/bin/env bash
# Build and run the recoil numeric test: the shipped C++ against Andyalpa's original Lua, frame by frame.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/build/CMakeCache.txt" ] || cmake -S "$HERE" -B "$HERE/build" -G "Visual Studio 17 2022" -A x64 >/dev/null
cmake --build "$HERE/build" --config Release 2>&1 | grep -E " error |warning C" || true
"$HERE/build/Release/recoil_test.exe" "$HERE/../../../original-lua/data/re8_vr/re8_vr_recoil.json" > "$HERE/build/cpp.csv"
lua "$HERE/recoil_test.lua" "$HERE/../../../original-lua/autorun/re8_vr_recoil.lua" > "$HERE/build/lua.csv"
python "$HERE/compare.py" "$HERE/build/cpp.csv" "$HERE/build/lua.csv"
