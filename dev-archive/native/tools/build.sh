#!/usr/bin/env bash
# Build visceral_re8_native.dll (Release x64) and check that it exports the two REFramework entry points.
#   bash dev-archive/native/tools/build.sh
# No --deploy yet: the Steam install runs the scope mod, and how Visceral RE8 sits beside it is still open
# (board row "Install layout"). Installing is a separate, backed-up step until that is settled.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$HERE/build"
[ -f "$BUILD/CMakeCache.txt" ] || cmake -S "$HERE" -B "$BUILD" -G "Visual Studio 17 2022" -A x64 >/dev/null
DLL="$BUILD/Release/visceral_re8_native.dll"
rm -f "$DLL"   # a failed build must never leave an old DLL behind
cmake --build "$BUILD" --config Release 2>&1 | tee "$BUILD/last-build.log" | grep -E "warning|error|Build succeeded|FAILED" || true
[ -f "$DLL" ] || { echo "BUILD FAILED"; exit 1; }
ls -l "$DLL"; sha256sum "$DLL"
for e in reframework_plugin_required_version reframework_plugin_initialize; do
    grep -q "$e" "$DLL" && echo "export $e: present" || { echo "export $e: MISSING"; exit 1; }
done
