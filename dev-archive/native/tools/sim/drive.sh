# drive.sh: launch Village on the simulator (VR Bench on) and drive to gameplay; prints each step
S="$(cd "$(dirname "$0")" && pwd)"; G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
powershell -NoProfile -Command "\$env:SteamAppId='1196590'; \$env:XR_RUNTIME_JSON=\"\$env:LOCALAPPDATA\Programs\OpenXR-Simulator\openxr_simulator.json\"; Start-Process -FilePath '$(cygpath -w "$G")\re8.exe' -WorkingDirectory '$(cygpath -w "$G")'"
sleep 8; n=0; until grep -aq "textures have been setup" "$G/re2_framework_log.txt" 2>/dev/null || [ $n -ge 60 ]; do sleep 2; n=$((n+1)); done
sleep 22; P=$(tasklist | grep -i re8 | awk '{print $2}' | head -1); echo $P > "$S/pid.txt"; echo "pid $P"
python "$S/vb.py" pass >/dev/null; python "$S/keys.py" $P >/dev/null
python "$S/vb.py" press right a 0.3; sleep 4      # title -> main menu
python "$S/vb.py" press right a 0.3; sleep 4      # Continue -> load question
python "$S/stick.py" left 0 1; sleep 1            # Yes
python "$S/vb.py" press right a 0.3; sleep 28     # load
python "$S/keys.py" $P >/dev/null; python "$S/vb.py" press right a 0.3; sleep 6   # chapter card
echo driven
