# one F2 shot then a left-hand bolt cycle; prints the loaded count
S="$(cd "$(dirname "$0")" && pwd)"; G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE/re2_framework_log.txt"; P=$(cat "$S/pid.txt")
python "$S/walk.py" set -0.30 1.1 -0.2 0 0 >/dev/null; python "$S/keys.py" $P >/dev/null
python "$S/hear.py" shot
sleep 1; python "$S/walk.py" set 0.0 1.43 -0.48 0 0 >/dev/null; sleep 0.5; python "$S/keys.py" $P >/dev/null
python "$S/walk.py" squeeze 1 >/dev/null; sleep 1; python "$S/walk.py" trigger 1 >/dev/null; sleep 1
STROKE_VEC=-0.58,-0.80,-0.11 python "$S/stroke2.py" 0.12 25 1.0 >/dev/null; sleep 2
python "$S/walk.py" trigger 0 >/dev/null; python "$S/walk.py" squeeze 0 >/dev/null; sleep 0.5
grep -a "bolt cycle complete" "$G" | tail -1 | cut -c60-200
