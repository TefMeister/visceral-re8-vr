#!/usr/bin/env bash
# install.sh -- rebuild 2's ONE install script (design 2026-11-25d, section 6 step 6). 2026-11-26.
#
#   bash dev-archive/rebuild2/tools/install.sh          install what files.txt lists, write the installed list
#   bash dev-archive/rebuild2/tools/install.sh --check  name every file under reframework/ that nobody accounts for
#
# files.txt: one line per file of ours, "<source, relative to rebuild2/> <target, relative to the game folder>".
# base.txt:  the files of the base (REFramework nightly + praydog's VR layer), relative to the game folder.
# Settings (re2_fw_config.txt) are changed by settings.txt lines "KEY=VALUE"; the file is backed up once per day first.
# Never run while the game is up. The old build.sh (dev-archive/native/tools) must NOT be run against this folder.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GAME="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
BACKUPS="/d/RE Village REFramework builds/rebuild-2-backups"
LIST="$GAME/reframework/data/visceral_re8/INSTALLED.txt"

if tasklist 2>/dev/null | grep -qi "re8.exe"; then
    echo "NOT INSTALLED: Village (re8.exe) is running"; exit 2
fi

check() {
    local bad=0
    while IFS= read -r f; do
        rel="${f#"$GAME"/}"
        grep -qxF "$rel" "$HERE/tools/base.txt" && continue
        awk '{print $2}' "$HERE/tools/files.txt" | grep -qxF "$rel" && continue
        case "$rel" in reframework/data/*) continue ;; esac   # settings and logs the game and the mod write
        echo "NOT ON ANY LIST: $rel"; bad=1
    done < <(find "$GAME/reframework" -type f)
    [ "$bad" = 0 ] && echo "folder check: every file under reframework/ is accounted for"
    return 0
}

if [ "${1:-}" = "--check" ]; then check; exit 0; fi

mkdir -p "$GAME/reframework/data/visceral_re8" "$BACKUPS"
: > "$LIST.new"
while read -r src dst; do
    [ -z "${src:-}" ] && continue
    case "$src" in \#*) continue ;; esac
    mkdir -p "$(dirname "$GAME/$dst")"
    cp "$HERE/$src" "$GAME/$dst"
    echo "$(sha256sum "$GAME/$dst" | cut -c1-16)  $dst" >> "$LIST.new"
    echo "installed: $dst"
done < "$HERE/tools/files.txt"

CFG="$GAME/re2_fw_config.txt"
if [ -f "$HERE/tools/settings.txt" ] && [ -f "$CFG" ]; then
    BK="$BACKUPS/re2_fw_config-$(date +%Y-%m-%d).txt"
    [ -f "$BK" ] || cp "$CFG" "$BK"
    while IFS='=' read -r key value; do
        [ -z "${key:-}" ] && continue
        case "$key" in \#*) continue ;; esac
        if grep -q "^$key=" "$CFG"; then
            sed -i "s|^$key=.*|$key=$value|" "$CFG"
        else
            echo "$key=$value" >> "$CFG"
        fi
        echo "setting: $key=$value" | tee -a "$LIST.new"
    done < "$HERE/tools/settings.txt"
fi
mv "$LIST.new" "$LIST"
check
