# trigtest.sh [ri id ...]: the right index finger's bend (three joints, degrees) at rest, with RT held 0.5 s and 2.5 s, and after
# release, per gun, with the finger script's own status. Tefa 2026-11-23: "index finger moving with RT press on the trigger".
S="$(cd "$(dirname "$0")" && pwd)"; cd "$S"; G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
Q="local sm=sdk.get_native_singleton('via.SceneManager'); local sc=sdk.call_native_func(sm, sdk.find_type_definition('via.SceneManager'), 'get_CurrentScene'); local ptf=sc:call('findComponents(System.Type)', sdk.typeof('app.PlayerUpdaterBase')):get_elements()[1]:call('get_GameObject'):call('get_Transform'); local o={} for _,n in ipairs({'R_IndexF1','R_IndexF2','R_IndexF3'}) do o[#o+1]=string.format('%.0f', ptf:call('getJointByName',n):call('get_LocalEulerAngle').z*57.3) end return table.concat(o,' ')"
python keys.py $(cat pid.txt) >/dev/null
for g in "${@:-ri3046}"; do echo "equip $g" > "$G/reframework/data/finger_rec/command.txt"; sleep 6; python keys.py $(cat pid.txt) >/dev/null
  python step.py right=0.05,0.03,0.40,90,55 left=-0.30,-0.35,0.25,0,0 squeeze=0 trigger=0 rtrigger=0 wait=1.0 >/dev/null; A=$(python rv.py "$Q")
  python step.py rtrigger=1 wait=0.5 >/dev/null; B=$(python rv.py "$Q"); sleep 2; C=$(python rv.py "$Q"); ST=$(python rv.py 'return tostring(_G.hand_poser_trigger)')
  python step.py rtrigger=0 wait=1.0 >/dev/null; D=$(python rv.py "$Q")
  echo "$g index: rest [$A] RT 0.5 s [$B] RT 2.5 s [$C] released [$D] | $ST"; done
