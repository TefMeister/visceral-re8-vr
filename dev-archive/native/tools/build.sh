#!/usr/bin/env bash
# Build visceral_re8_native.dll (Release x64), check that it exports the two REFramework entry points, and optionally
# install Visceral RE8 on top of the scope mod v1.1.5 in the Steam game (Tefa 2026-10-15: "use the 1.1.5 scope mod as a
# base for our Visceral mod and just build on top of it").
#   bash dev-archive/native/tools/build.sh             build only
#   bash dev-archive/native/tools/build.sh --deploy    build, back up every game file it touches, install
#   bash dev-archive/native/tools/build.sh --undo DIR  put a --deploy backup back (DIR = the folder --deploy printed)
# A deploy never overwrites a saved settings file (reframework/data/...): those are the player's, copied only if absent.
# Roll back by hand at any time: the v1.1.5 zip + deleting the files listed in the backup's ADDED.txt.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PACK="$HERE/../original-lua"                     # Andyalpa's pack as received; the not-yet-ported files ship from here
GAME="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
BACKUPS="/d/RE Village REFramework builds"
BUILD="$HERE/build"
# pack files already ported to C++ (their Lua must NOT run beside the plugin)
PORTED=(re8_vr_haptics.lua re8_vr_recoil.lua re8_vr_ammo_hud.lua)

undo() {
    local dir="$1"
    [ -f "$dir/ADDED.txt" ] || { echo "not a deploy backup: $dir"; exit 1; }
    while IFS= read -r rel; do [ -n "$rel" ] && rm -f "$GAME/$rel" && echo "removed $rel"; done < "$dir/ADDED.txt"
    (cd "$dir/files" 2>/dev/null && find . -type f | while IFS= read -r f; do mkdir -p "$GAME/$(dirname "$f")"; cp -p "$f" "$GAME/$f"; echo "restored ${f#./}"; done) || true
    echo "undo done from $dir"
}
if [ "${1:-}" = "--undo" ]; then undo "${2:?usage: build.sh --undo <backup folder>}"; exit 0; fi

[ -f "$BUILD/CMakeCache.txt" ] || cmake -S "$HERE" -B "$BUILD" -G "Visual Studio 17 2022" -A x64 >/dev/null
DLL="$BUILD/Release/visceral_re8_native.dll"
rm -f "$DLL"   # a failed build must never leave an old DLL behind
cmake --build "$BUILD" --config Release 2>&1 | tee "$BUILD/last-build.log" | grep -E "warning|error|Build succeeded|FAILED" || true
[ -f "$DLL" ] || { echo "BUILD FAILED"; exit 1; }
ls -l "$DLL"; sha256sum "$DLL"
for e in reframework_plugin_required_version reframework_plugin_initialize; do
    grep -q "$e" "$DLL" && echo "export $e: present" || { echo "export $e: MISSING"; exit 1; }
done
[ "${1:-}" = "--deploy" ] || exit 0

[ -f "$GAME/re8.exe" ] || { echo "game not found at $GAME"; exit 1; }
BK="$BACKUPS/_backup-$(date +%Y-%m-%d-%H%M)-before-visceral-re8-deploy"
mkdir -p "$BK/files"; : > "$BK/ADDED.txt"
# put(src, rel, mode): mode "code" overwrites (after backing up), "settings" only fills a missing file
put() {
    local src="$1" rel="$2" mode="$3" dst="$GAME/$2"
    if [ -f "$dst" ]; then
        [ "$mode" = settings ] && { echo "kept   $rel (player's settings)"; return; }
        cmp -s "$src" "$dst" && { echo "same   $rel"; return; }
        mkdir -p "$BK/files/$(dirname "$rel")"; cp -p "$dst" "$BK/files/$rel"
        echo "update $rel"
    else
        echo "$rel" >> "$BK/ADDED.txt"; echo "add    $rel"
    fi
    mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"
}
put "$DLL" reframework/plugins/visceral_re8_native.dll code
put "$HERE/sfx/bolt_click.wav" reframework/data/visceral_re8/sfx/bolt_click.wav code   # Andyalpa's click (RE7 VR Reloaded)
# ours, plus our copies of pack files (Andyalpa's + our changes): re8_vr.lua (switches), and the holster, its visuals and
# the hand gestures with the loading-flood guard (2026-10-24)
for f in visceral_re8_bridge.lua visceral_re8_menu.lua visceral_re8_sounds.lua re8_vr.lua jitterlog.lua \
         re8_vr_holster.lua re8_vr_holster_visuals.lua re8_vr_hand_gestures.lua; do
    put "$HERE/lua/$f" "reframework/autorun/$f" code
done
for f in "$PACK"/autorun/*.lua; do
    b="$(basename "$f")"
    [ -f "$HERE/lua/$b" ] && continue                         # our copy of it went in above
    for p in "${PORTED[@]}"; do [ "$b" = "$p" ] && continue 2; done
    put "$f" "reframework/autorun/$b" code
done
(cd "$PACK/data" && find . -type f) | while IFS= read -r f; do put "$PACK/data/$f" "reframework/data/${f#./}" settings; done
# a ported pack file left in the game from an earlier hand install would run twice: move it into the backup
for p in "${PORTED[@]}"; do
    if [ -f "$GAME/reframework/autorun/$p" ]; then
        mkdir -p "$BK/files/reframework/autorun"; mv "$GAME/reframework/autorun/$p" "$BK/files/reframework/autorun/$p"
        echo "moved  reframework/autorun/$p out (ported to C++)"
    fi
done
echo "deployed; backup + ADDED.txt in: $BK"
echo "undo:  bash dev-archive/native/tools/build.sh --undo \"$BK\""
