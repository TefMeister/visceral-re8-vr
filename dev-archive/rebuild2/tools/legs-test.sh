#!/usr/bin/env bash
# legs-test.sh -- rebuild 2 (2026-11-26, RE8-091): sets ONE start of the legs' halving test. Tefa: "legs glitchy when
# walking"; already cleared by his own live comparisons: the body turn's free zone, the body's follow lag, steps
# instead of sliding. One switch set per start of the game; the recorder (native/src/rec.h) stamps every walk file
# with the switches that were in, and tools/walkread.py counts the fault, so each start needs about 20 s of walking.
#
#   bash legs-test.sh status      what is set now, and the walk files so far (one line each)
#   bash legs-test.sh all-on      start 0: everything on (the fault as Tefa saw it, now measured)
#   bash legs-test.sh bare        start 1: the plugin off AND the script half of the body off = the bare base
#   bash legs-test.sh frame       start 2: only the plugin off (the script's body place and steps stay on)
#   bash legs-test.sh bodyturn    start 3: only the body turn off (the still spine goes off with it)
#   bash legs-test.sh bodyturn-walk   start 4: only "the walk follows the head" off
#   bash legs-test.sh spinestill  start 5: only the still spine off
#   bash legs-test.sh scriptbody  only the script half off (the plugin stays on)
#
# HOW TO READ IT (the fault = walkread's "leg snaps" or "motion restarts" well above 0):
#   start 0 clean                    -> the fault needs something this walk did not do; walk as in the clip
#   start 1 (bare) STILL has it      -> it is the base's (praydog's layer or the game), not ours: stop halving
#   start 1 clean, start 2 has it    -> the script half: the body's place or the steps
#   start 2 clean, start 3 has it    -> a plugin part other than the body turn (fingers, sleeping hands, doors ...)
#   start 3 clean, start 4 clean     -> the stick turned by head minus body ("the walk follows the head")
#   start 3 clean, start 4 has it    -> the body turn's answer to the game; start 5 says whether the spine is in it
# Refuses while the game runs (off.txt is read once, at the start). Changes two small files in the game's data
# folder and nothing else; `all-on` takes both away again.
set -euo pipefail
GAME="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
DATA="$GAME/reframework/data/visceral_re8"
HERE="$(cd "$(dirname "$0")" && pwd)"
what="${1:-status}"

if [ "$what" = "status" ]; then
    echo "off.txt: $( [ -f "$DATA/off.txt" ] && tr '\n' ' ' < "$DATA/off.txt" || echo "(none: everything on)")"
    echo "script half of the body: $( [ -f "$DATA/scriptbody-off.json" ] && echo OFF || echo on)"
    python "$HERE/walkread.py" all 2>/dev/null || true
    exit 0
fi
if tasklist 2>/dev/null | grep -qi "re8.exe"; then echo "NOT SET: Village (re8.exe) is running; the switches are read at its start"; exit 2; fi
mkdir -p "$DATA"
case "$what" in
    all-on)        words="" ;;
    bare)          words="frame scriptbody" ;;
    frame|bodyturn|bodyturn-walk|spinestill|scriptbody) words="$what" ;;
    *) echo "unknown: $what (status, all-on, bare, frame, bodyturn, bodyturn-walk, spinestill, scriptbody)"; exit 1 ;;
esac
rm -f "$DATA/off.txt" "$DATA/scriptbody-off.json"
[ -z "$words" ] || echo "$words" > "$DATA/off.txt"
case " $words " in *" scriptbody "*) echo '{"off": 1}' > "$DATA/scriptbody-off.json" ;; esac
echo "set for the next start: ${words:-everything on}"
