# enter_real.sh: after drive_real_slot.sh (the slot picture LOOKED AT first): A, A (Yes), 36 s, A, 15 s (the dev guns top up),
# then keep.py on and the head's place printed as HV_HEAD. 2026-11-23.
S="$(cd "$(dirname "$0")" && pwd)"; P=$(cat "$S/pid.txt")
python "$S/keys.py" $P >/dev/null; python "$S/vb.py" Village press a; sleep 2.5; python "$S/vb.py" Village press a; sleep 36
python "$S/keys.py" $P >/dev/null; python "$S/vb.py" Village press a; sleep 15
(python "$S/keep.py" 20000 >/dev/null 2>&1 &); sleep 1
python "$S/rv.py" "local t=vrmod:get_transform(0); return string.format('HV_HEAD=\"%.3f %.3f %.3f %.3f %.3f\"', t[3].x, t[3].y, t[3].z, -t[2].x, -t[2].z)"
