# drive_real_re.sh <re2|re3>: start RE2 or RE3 through the REAL headset lying on the desk (VR Bench on, no simulator), wait for the
# title, take a picture. Presses nothing: look at the picture, then `vb.py x press a` (RE2: three times, RE3: four) with pictures
# between. Sets pid.txt. Use RV_GAME_DIR=<game folder> with rv.py / step.py afterwards. 2026-11-23.
S="$(cd "$(dirname "$0")" && pwd)"
case "$1" in re2) G="/c/Steam/steamapps/common/RESIDENT EVIL 2  BIOHAZARD RE2"; EXE=re2.exe; APP=883710;; re3) G="/c/Steam/steamapps/common/RE3"; EXE=re3.exe; APP=952060;; *) echo "re2 or re3"; exit 1;; esac
[ -f "$G/$EXE" ] || { echo "no $EXE in $G"; exit 1; }
VB="$HOME/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"
python "$VB/vrbench.py" start "$(cygpath -w "$G/$EXE")" | tail -1
powershell -NoProfile -Command "\$env:SteamAppId='$APP'; Start-Process -FilePath '$(cygpath -w "$G")\$EXE' -WorkingDirectory '$(cygpath -w "$G")'"
sleep 8; n=0; until grep -aq "textures have been setup" "$G/re2_framework_log.txt" 2>/dev/null || [ $n -ge 60 ]; do sleep 2; n=$((n+1)); done
grep -aq "textures have been setup" "$G/re2_framework_log.txt" || echo "NO 'textures have been setup' after 2 minutes: Suspending $(grep -ac Suspending "$G/re2_framework_log.txt") / Resuming $(grep -ac Resuming "$G/re2_framework_log.txt") (unequal = the loader's start-up hang)"
sleep 25; P=$(tasklist | grep -i "$EXE" | awk '{print $2}' | head -1); echo $P > "$S/pid.txt"; echo "pid $P"
python "$S/keep.py" stop; python "$S/keys.py" $P >/dev/null; RV_GAME_DIR="$(cygpath -w "$G")" python "$S/shot.py" "${TMPDIR:-/tmp}/re_title.png" 0.8 >/dev/null; echo "title picture: ${TMPDIR:-/tmp}/re_title.png"
