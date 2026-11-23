# trigsolve.sh <ri id> ...: the right index finger fitted onto each gun's own Trigger joint through the Hand Poser window
# (2026-11-23): the last joint 1.2 cm under the pivot and 1.3 cm in front of it, the fingertip down the blade's face (the WCX's
# fit, which pictured as a finger on the trigger), solved by solve.py in the gun's frame; then trigfit.py says where the pad is.
S="$(cd "$(dirname "$0")" && pwd)"; cd "$S"; G="${RV_GAME_DIR:-/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE}"
for gun in "$@"; do
  echo "== $gun"; echo "equip $gun" > "$G/reframework/data/finger_rec/command.txt"; sleep 7
  read tx ty tz < <(python rv.py -f q_gunframe.lua | awk '$2=="Trigger"{print $3, $4, $5}')
  [ -z "$tz" ] && { echo "no Trigger joint"; continue; }
  f3=$(python -c "print('%.1f,%.1f,%.1f' % ($tx + 0.3, $ty - 1.2, $tz + 1.3))"); tip=$(python -c "print('%.1f,%.1f,%.1f' % ($tx + 0.8, $ty - 3.4, $tz + 0.9))")
  SOLVE_Q=q_gunframe.lua python solve.py side=R IndexF3=$f3,2 Indextip=$tip vars=I1.z,I1.y,I2.z,I3.z rounds=4 | tail -3
  python trigfit.py "$gun"
done
