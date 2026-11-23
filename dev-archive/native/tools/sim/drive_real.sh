# drive_real.sh: launch Village through the REAL headset (lying on the desk, Virtual Desktop streaming) with VR Bench on,
# and drive to gameplay (A, A, left stick up, A, wait, A). Needs VR_RenderingTechnique_V2=1 for the desktop picture.
# 2026-11-23. Starts keep.py too (the pose kept alive). Writes pid.txt.
S="$(cd "$(dirname "$0")" && pwd)"; G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
VB="$HOME/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"
python "$VB/vrbench.py" start "$(cygpath -w "$G/re8.exe")" | tail -1
powershell -NoProfile -Command "\$env:SteamAppId='1196590'; Start-Process -FilePath '$(cygpath -w "$G")\re8.exe' -WorkingDirectory '$(cygpath -w "$G")'"
sleep 8; n=0; until grep -aq "textures have been setup" "$G/re2_framework_log.txt" 2>/dev/null || [ $n -ge 60 ]; do sleep 2; n=$((n+1)); done
sleep 30; P=$(tasklist | grep -i re8 | awk '{print $2}' | head -1); echo $P > "$S/pid.txt"; echo "pid $P"
python "$S/keep.py" stop; sleep 0.5
python "$S/keys.py" $P >/dev/null; python "$S/vb.py" Village press a; sleep 4
python "$S/keys.py" $P >/dev/null; python "$S/vb.py" Village press a; sleep 4
python "$S/keys.py" $P >/dev/null; python "$S/stick.py" left 0 1; sleep 1; python "$S/stick.py" left 0 0
python "$S/keys.py" $P >/dev/null; python "$S/vb.py" Village press a; sleep 32
python "$S/keys.py" $P >/dev/null; python "$S/vb.py" Village press a; sleep 7
(nohup python "$S/keep.py" 7200 >/dev/null 2>&1 &)
python "$S/rv.py" --front "return re8vr ~= nil and re8vr.player ~= nil" | tail -1
