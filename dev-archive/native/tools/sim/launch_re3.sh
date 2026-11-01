# launch_re3.sh: launch RE3 on the simulator (VR Bench on); its REFramework log is re2_framework_log.txt
S="$(cd "$(dirname "$0")" && pwd)"; G="/c/Steam/steamapps/common/RE3"
powershell -NoProfile -Command "\$env:SteamAppId='952060'; \$env:XR_RUNTIME_JSON=\"\$env:LOCALAPPDATA\Programs\OpenXR-Simulator\openxr_simulator.json\"; Start-Process -FilePath '$(cygpath -w "$G")\re3.exe' -WorkingDirectory '$(cygpath -w "$G")'"
sleep 8; n=0; until grep -aq "textures have been setup" "$G/re2_framework_log.txt" 2>/dev/null || [ $n -ge 60 ]; do sleep 2; n=$((n+1)); done
sleep 22; P=$(tasklist | grep -i re3 | awk '{print $2}' | head -1); echo $P > "$S/pid.txt"; echo "pid $P"
echo launched
