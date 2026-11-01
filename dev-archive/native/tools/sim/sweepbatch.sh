# sweepbatch.sh <re2|re3> <wp>...: (re)start the game on the simulator, drive into play, run gunsweep.py on these guns
S="$(cd "$(dirname "$0")" && pwd)"; GAME=$1; shift
P=$(cat "$S/pid.txt" 2>/dev/null); if [ -n "$P" ] && tasklist | grep -q " $P "; then python "$S/wins.py" $P via >/dev/null; n=0; while tasklist | grep -q " $P " && [ $n -lt 40 ]; do sleep 1; n=$((n+1)); done; fi
if [ $GAME = re3 ]; then bash "$S/launch_re3.sh" >/dev/null; N=4; W=14; else bash "$S/launch_re2.sh" >/dev/null; N=3; W=8; fi
sleep 25; P=$(cat "$S/pid.txt"); python "$S/vb.py" pass >/dev/null
for i in $(seq 1 $N); do python "$S/keys.py" $P >/dev/null; python "$S/vb.py" press right a 0.3 >/dev/null; sleep 4; done; sleep $W
python "$S/keys.py" $P >/dev/null; python "$S/gunsweep.py" $GAME "$@"
