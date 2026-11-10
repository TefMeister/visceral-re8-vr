# drive.sh: launch Village on the simulator (VR Bench on) and drive to gameplay; prints each step
# (2026-11-08: vb.py's usage is now `vb.py <window title> press <button>`; the old `vb.py press right a` and `vb.py pass` failed)
S="$(cd "$(dirname "$0")" && pwd)"; G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
powershell -NoProfile -Command "\$env:SteamAppId='1196590'; \$env:XR_RUNTIME_JSON=\"\$env:LOCALAPPDATA\Programs\OpenXR-Simulator\openxr_simulator.json\"; Start-Process -FilePath '$(cygpath -w "$G")\re8.exe' -WorkingDirectory '$(cygpath -w "$G")'"
sleep 8; n=0; until grep -aq "textures have been setup" "$G/re2_framework_log.txt" 2>/dev/null || [ $n -ge 60 ]; do sleep 2; n=$((n+1)); done
sleep 22; P=$(tasklist | grep -i re8 | awk '{print $2}' | head -1); echo $P > "$S/pid.txt"; echo "pid $P"
python "$S/keys.py" $P >/dev/null
python "$S/keys.py" $P >/dev/null; python "$S/vb.py" Village press a; sleep 4      # title -> main menu
python "$S/keys.py" $P >/dev/null; python "$S/vb.py" Village press a; sleep 4      # Continue -> load question
python "$S/keys.py" $P >/dev/null; python "$S/stick.py" left 0 1; sleep 1            # Yes
python "$S/keys.py" $P >/dev/null; python "$S/vb.py" Village press a; sleep 28     # load
python "$S/keys.py" $P >/dev/null; python "$S/keys.py" $P >/dev/null; python "$S/vb.py" Village press a; sleep 6   # chapter card
echo driven
# 2026-11-10: a guard. Once the presses landed on NEW GAME instead of the save (the view-mode and difficulty questions
# came up; nothing was confirmed or saved). If the game is not plainly in play now, it is closed and this says so.
T=$(python "$S/rv.py" --front "local t = sdk.get_managed_singleton('app.GUIManager'):get_field('exclusiveTarget'); return re8vr ~= nil and re8vr.player ~= nil, t and t:get_type_definition():get_full_name() or 'none'" 2>/dev/null)
case "$T" in
  *CameraTypeSetting*|*GUIDifficulty*|*GUIMainMenu*|*GUITitle*)
    echo "WRONG MENU ($T): closing the game, nothing confirmed"; python "$S/close_village.py" >/dev/null 2>&1; exit 3;;
  true*) echo "in play ($T)";;
  *) echo "state unknown ($T)";;
esac
