# drive_real_slot.sh <slot rows down from Auto Save, e.g. 6>: launch Village through the REAL headset (on the desk), VR Bench on,
# and load that save from the Load Game list (A, flick up 2 = New Game, flick down 1 = Load Game, A, flick down N, A, A).
# Stops with a picture path if the title is not showing. 2026-11-23.
S="$(cd "$(dirname "$0")" && pwd)"; G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"; N="${1:-6}"
VB="$HOME/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"
# 2026-11-23: the desk headset had gone to sleep once and the game started flat: ask first (waits up to 3 minutes for it).
python "$S/headset_up.py" 180 || { echo "HEADSET NOT STREAMING: nothing launched"; exit 4; }
python "$VB/vrbench.py" start "$(cygpath -w "$G/re8.exe")" | tail -1
powershell -NoProfile -Command "\$env:SteamAppId='1196590'; Start-Process -FilePath '$(cygpath -w "$G")\re8.exe' -WorkingDirectory '$(cygpath -w "$G")'"
# 2026-11-23: REFramework's own start-up can deadlock (its log ends in "Suspending <thread>" lines with fewer "Resuming" ones, the
# window black and not answering; seen once in about ten starts). hung(): the log has stood still 25 s with threads still paused.
hung() { local L="$G/re2_framework_log.txt"; [ -f "$L" ] || return 1; local a=$(stat -c %s "$L"); sleep 25; [ "$a" = "$(stat -c %s "$L")" ] && [ "$(grep -ac Suspending "$L")" -gt "$(grep -ac Resuming "$L")" ] && ! grep -aq "textures have been setup" "$L"; }
sleep 8
if hung; then echo "START-UP HANG (the loader's threads never resumed): ending it and starting once more"; cp "$G/re2_framework_log.txt" "${TMPDIR:-/tmp}/village_hung_log.txt"; taskkill //F //IM re8.exe >/dev/null 2>&1; sleep 5
  powershell -NoProfile -Command "\$env:SteamAppId='1196590'; Start-Process -FilePath '$(cygpath -w "$G")\re8.exe' -WorkingDirectory '$(cygpath -w "$G")'"; sleep 8; fi
n=0; until grep -aq "textures have been setup" "$G/re2_framework_log.txt" 2>/dev/null || [ $n -ge 60 ]; do sleep 2; n=$((n+1)); done
sleep 35; P=$(tasklist | grep -i re8 | awk '{print $2}' | head -1); echo $P > "$S/pid.txt"; echo "pid $P"
python "$S/keep.py" stop; T="${TMPDIR:-/tmp}/village_title.png"; python "$S/shot.py" "$T" 0.6 >/dev/null
B=$(python -c "from PIL import Image, ImageStat; print(int(sum(ImageStat.Stat(Image.open(r'$(cygpath -w "$T")').convert('RGB')).mean)/3))")
[ "$B" -lt 30 ] && { echo "TITLE NOT SHOWING (brightness $B): nothing pressed; picture $T"; exit 3; }
python "$S/keys.py" $P >/dev/null; python "$S/vb.py" Village press a; sleep 4
python "$S/keys.py" $P >/dev/null; python "$S/flick.py" up 2; python "$S/flick.py" down 1; sleep 0.5
python "$S/vb.py" Village press a; sleep 3.5; python "$S/flick.py" down "$N"; sleep 0.5
python "$S/shot.py" "${TMPDIR:-/tmp}/village_slot.png" 0.8 >/dev/null; echo "slot picture: ${TMPDIR:-/tmp}/village_slot.png"
