#!/usr/bin/env bash
# build.sh -- rebuild 2: build visceral_re8.dll (Release x64), run the rule-set scans, check the exports.
#   bash dev-archive/rebuild2/tools/build.sh             build + scans
#   bash dev-archive/rebuild2/tools/build.sh --install   ... then tools/install.sh (refuses while the game runs)
# The scans (design 2026-11-25d section 5) FAIL the build:
#   rule 1   no source file names BeginRendering as a callback (comments may say why not)
#   rule 2/3 no source file but jointwriter.cpp names a via.Joint setter
#   size     no hand-written source file over 800 lines
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/native/src"
BUILD="$HERE/native/build"
DLL="$BUILD/Release/visceral_re8.dll"

fail=0
# a callback is registered with the entry's name as a string literal: "BeginRendering"
if grep -n '"BeginRendering"' "$SRC"/*.cpp "$SRC"/*.h; then echo "SCAN FAILED (rule 1): BeginRendering used as a callback"; fail=1; fi
if grep -n '"set_LocalRotation"\|"set_LocalPosition"\|"set_Rotation"\|"set_Position"\|"set_LocalScale"' "$SRC"/*.cpp "$SRC"/*.h | grep -v "jointwriter.cpp"; then
    echo "SCAN FAILED (rules 2-3): a joint or transform setter outside jointwriter.cpp"; fail=1
fi
for f in "$SRC"/*.cpp "$SRC"/*.h; do
    n=$(wc -l < "$f"); [ "$n" -le 800 ] || { echo "SCAN FAILED (size): $(basename "$f") has $n lines"; fail=1; }
done
if grep -n '"BeginRendering"' "$HERE"/lua/visceral_re8_*.lua; then echo "SCAN FAILED (rule 11): one of our scripts hooks BeginRendering"; fail=1; fi
[ "$fail" = 0 ] || exit 1
echo "scans: clean"

[ -f "$BUILD/CMakeCache.txt" ] || cmake -S "$HERE/native" -B "$BUILD" -G "Visual Studio 17 2022" -A x64 >/dev/null
rm -f "$DLL"   # a failed build must never leave an old DLL behind
cmake --build "$BUILD" --config Release 2>&1 | tee "$BUILD/last-build.log" | grep -E "warning|error|FAILED" || true
[ -f "$DLL" ] || { echo "BUILD FAILED"; exit 1; }
ls -l "$DLL"; sha256sum "$DLL"
for e in reframework_plugin_required_version reframework_plugin_initialize; do
    grep -q "$e" "$DLL" && echo "export $e: present" || { echo "export $e: MISSING"; exit 1; }
done
# the maths check: the shipped base.cpp against sums built another way (native/tests/mathtest.cpp)
cmake --build "$BUILD" --config Release --target mathtest >/dev/null 2>&1 && "$BUILD/Release/mathtest.exe" || { echo "MATHS CHECK FAILED"; exit 1; }
[ "${1:-}" = "--install" ] || exit 0
bash "$HERE/tools/install.sh"
