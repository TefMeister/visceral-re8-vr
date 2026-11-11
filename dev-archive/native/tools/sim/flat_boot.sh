# flat_boot.sh: launch Village on the FLAT screen (works with a headset streaming too: the VR start is made to fail) and
# drive it into the save: Insert (the overlay), Enter (title), F (Continue), Up, F (Yes), the load, F (chapter card).
# 2026-11-11, from KNOWN.md's flat boot route; writes pid.txt. Needs zz_visceral_eval.lua in autorun for the last check.
S="$(cd "$(dirname "$0")" && pwd)"; G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
powershell -NoProfile -Command "\$env:SteamAppId='1196590'; \$env:XR_RUNTIME_JSON='C:\no-such-runtime.json'; Start-Process -FilePath '$(cygpath -w "$G")\re8.exe' -WorkingDirectory '$(cygpath -w "$G")'"
sleep 45; P=$(tasklist | grep -i "re8.exe" | awk '{print $2}' | head -1); echo $P > "$S/pid.txt"; echo "pid $P"
python "$S/keys.py" $P insert >/dev/null; sleep 1
python "$S/keys.py" $P enter >/dev/null; sleep 4
python "$S/keys.py" $P f >/dev/null; sleep 3
python "$S/keys.py" $P up >/dev/null
python "$S/keys.py" $P f >/dev/null; sleep 40
python "$S/keys.py" $P f >/dev/null; sleep 6
# in play = the player stands somewhere and a camera exists (the menu's exclusiveTarget stays on the old dialog, so it tells nothing)
python "$S/rv.py" --front 'local p = re8vr.player and re8vr.player:call("get_Transform"):call("get_Position"); return p ~= nil and "in play" or "NOT in play", visceral_re8_bridge.r(97)'
