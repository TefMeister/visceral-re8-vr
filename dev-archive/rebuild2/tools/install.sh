#!/usr/bin/env bash
# install.sh -- rebuild 2's ONE install script (design 2026-11-25d, section 6 step 6). 2026-11-26.
#
#   bash dev-archive/rebuild2/tools/install.sh          install what files.txt lists, write the installed list
#   bash dev-archive/rebuild2/tools/install.sh --check  name every file under reframework/ that nobody accounts for
#
# files.txt: one line per file of ours, "<source, relative to rebuild2/> <target, relative to the game folder>".
#            A third word "keep" = tuning the mod or Tefa changes in play: put in only when the game folder has
#            none (a fresh install), never written over.
# A file an earlier install put in that files.txt no longer lists is MOVED to the backups folder (kept, never
# deleted), so the game folder holds only what the list says.
# base.txt:  the files of the base (REFramework nightly + praydog's VR layer), relative to the game folder.
# Settings (re2_fw_config.txt) are changed by settings.txt lines "KEY=VALUE"; the file is backed up once per day first.
# Never run while the game is up. The old build.sh (dev-archive/native/tools) must NOT be run against this folder.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GAME="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
BACKUPS="/d/RE Village REFramework builds/rebuild-2-backups"
LIST="$GAME/reframework/data/visceral_re8/INSTALLED.txt"
# 2026-11-26: a clone that checks text out with Windows line ends hands every list line a trailing carriage
# return; a file was installed under a name ending in one (found the same hour, nothing lost). Every list is
# read through this.
lines() { tr -d '\r' < "$1"; }

if tasklist 2>/dev/null | grep -qi "re8.exe"; then
    echo "NOT INSTALLED: Village (re8.exe) is running"; exit 2
fi

check() {
    local bad=0
    while IFS= read -r f; do
        rel="${f#"$GAME"/}"
        lines "$HERE/tools/base.txt" | grep -qxF "$rel" && continue
        lines "$HERE/tools/files.txt" | awk '{print $2}' | grep -qxF "$rel" && continue
        case "$rel" in reframework/data/*) continue ;; esac   # settings and logs the game and the mod write
        echo "NOT ON ANY LIST: $rel"; bad=1
    done < <(find "$GAME/reframework" -type f)
    [ "$bad" = 0 ] && echo "folder check: every file under reframework/ is accounted for"
    return 0
}

if [ "${1:-}" = "--check" ]; then check; exit 0; fi

mkdir -p "$GAME/reframework/data/visceral_re8" "$BACKUPS"
# what an earlier install put in and the list no longer names: out of the game folder, kept in the backups
if [ -f "$LIST" ]; then
    while read -r _hash old; do
        [ -z "${old:-}" ] && continue
        case "$_hash" in setting:) continue ;; esac
        lines "$HERE/tools/files.txt" | awk '$1 !~ /^#/ {print $2}' | grep -qxF "$old" && continue
        [ -f "$GAME/$old" ] || continue
        OUT="$BACKUPS/taken-out-$(date +%Y-%m-%d-%H%M)"
        mkdir -p "$OUT/$(dirname "$old")"
        mv "$GAME/$old" "$OUT/$old"
        echo "taken out (no longer on the list, kept in the backups): $old"
    done < <(lines "$LIST")
fi
: > "$LIST.new"
while read -r src dst mode; do
    [ -z "${src:-}" ] && continue
    case "$src" in \#*) continue ;; esac
    mkdir -p "$(dirname "$GAME/$dst")"
    if [ "${mode:-}" = "keep" ] && [ -f "$GAME/$dst" ]; then
        echo "$(sha256sum "$GAME/$dst" | cut -c1-16)  $dst" >> "$LIST.new"
        echo "kept as it is: $dst"
        continue
    fi
    cp "$HERE/$src" "$GAME/$dst"
    echo "$(sha256sum "$GAME/$dst" | cut -c1-16)  $dst" >> "$LIST.new"
    echo "installed: $dst"
done < <(lines "$HERE/tools/files.txt")

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
    done < <(lines "$HERE/tools/settings.txt")
fi
mv "$LIST.new" "$LIST"
check
