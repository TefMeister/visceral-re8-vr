# drive_real_slot.sh <slot rows down from Auto Save, e.g. 6>: launch Village through the REAL headset (on the desk), VR Bench on,
# and load that save from the Load Game list (A, flick up 2 = New Game, flick down 1 = Load Game, A, flick down N, A, A).
# Stops with a picture path if the title is not showing. 2026-11-23.
S="$(cd "$(dirname "$0")" && pwd)"; G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"; N="${1:-6}"
VB="$HOME/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"
python "$VB/vrbench.py" start "$(cygpath -w "$G/re8.exe")" | tail -1
powershell -NoProfile -Command "\$env:SteamAppId='1196590'; Start-Process -FilePath '$(cygpath -w "$G")\re8.exe' -WorkingDirectory '$(cygpath -w "$G")'"
sleep 8; n=0; until grep -aq "textures have been setup" "$G/re2_framework_log.txt" 2>/dev/null || [ $n -ge 60 ]; do sleep 2; n=$((n+1)); done
sleep 35; P=$(tasklist | grep -i re8 | awk '{print $2}' | head -1); echo $P > "$S/pid.txt"; echo "pid $P"
python "$S/keep.py" stop; T="${TMPDIR:-/tmp}/village_title.png"; python "$S/shot.py" "$T" 0.6 >/dev/null
B=$(python -c "from PIL import Image, ImageStat; print(int(sum(ImageStat.Stat(Image.open(r'$(cygpath -w "$T")').convert('RGB')).mean)/3))")
[ "$B" -lt 30 ] && { echo "TITLE NOT SHOWING (brightness $B): nothing pressed; picture $T"; exit 3; }
python "$S/keys.py" $P >/dev/null; python "$S/vb.py" Village press a; sleep 4
python "$S/keys.py" $P >/dev/null; python "$S/flick.py" up 2; python "$S/flick.py" down 1; sleep 0.5
python "$S/vb.py" Village press a; sleep 3.5; python "$S/flick.py" down "$N"; sleep 0.5
python "$S/shot.py" "${TMPDIR:-/tmp}/village_slot.png" 0.8 >/dev/null; echo "slot picture: ${TMPDIR:-/tmp}/village_slot.png"
