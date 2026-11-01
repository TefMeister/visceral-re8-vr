# gm79test.sh: RE2 on the simulator: the GM 79's whole round trip with the test hand. Needs zz_test_short2.lua installed
# and VR Bench on. Prints the log lines that matter.
S="$(cd "$(dirname "$0")" && pwd)"; G="/c/Steam/steamapps/common/RESIDENT EVIL 2  BIOHAZARD RE2"; L="$G/re2_framework_log.txt"
bash "$S/launch_re2.sh" | tail -1; sleep 25; P=$(cat "$S/pid.txt"); python "$S/vb.py" pass >/dev/null
for i in 1 2 3; do python "$S/keys.py" $P >/dev/null; python "$S/vb.py" press right a 0.3 >/dev/null; sleep 4; done; sleep 8
for r in '{"imcall": "addItemCount(app.ropeway.gamemastering.Item.ID, System.Int32)", "args": [22, 4]}' '{"gift": "WP4100", "count": 1, "item": 22}'; do
  echo "$r" > "$G/reframework/data/zz_short.json"; python "$S/keys.py" $P >/dev/null; sleep 3; done
python - "$S" <<'PY'
import sys, time, json; sys.path.insert(0, sys.argv[1]); import walk
p={"right":[0.15,1.45,-0.35,90,60],"left":[-0.30,1.1,-0.2,0,0],"squeeze":0.0,"trigger":0.0,"rsqueeze":0.0}
walk.put(p); time.sleep(0.8); json.dump(p,open(sys.argv[1]+"/pose_now.json","w"))
PY
python "$S/keys.py" $P >/dev/null; echo "1 fire: $(python "$S/hear.py" gm79-a 2>&1 | tail -1 | cut -c1-24)"
python - "$S" <<'PY'
import sys, time; sys.path.insert(0, sys.argv[1]); import walk
R=[0.15,1.45,-0.35,90,60]; p={"right":R,"left":[-0.08,1.37,-0.43,0,0],"squeeze":0.0,"trigger":0.0,"rsqueeze":0.0}
def lt(): p["trigger"]=1.0; walk.put(p); time.sleep(0.25); p["trigger"]=0.0; walk.put(p); time.sleep(0.6)
walk.put(p); time.sleep(0.5); p["squeeze"]=1.0; walk.put(p); time.sleep(0.4); lt()          # open
p["squeeze"]=0.0; walk.put(p); time.sleep(0.3)
p["left"]=[-0.20,1.08,-0.02,0,0]; walk.put(p); time.sleep(0.6); p["squeeze"]=1.0; walk.put(p); time.sleep(0.8)   # a round
PY
echo "2 load: $(python "$S/portseek2.py" 0.05 1.40 -0.38)"
python - "$S" <<'PY'
import sys, time; sys.path.insert(0, sys.argv[1]); import walk
R=[0.15,1.45,-0.35,90,60]; p={"right":R,"left":[-0.08,1.37,-0.43,0,0],"squeeze":0.0,"trigger":0.0,"rsqueeze":0.0}
walk.put(p); time.sleep(0.5); p["squeeze"]=1.0; walk.put(p); time.sleep(0.4)
p["trigger"]=1.0; walk.put(p); time.sleep(0.25); p["trigger"]=0.0; walk.put(p); time.sleep(0.6)   # shut
p["squeeze"]=0.0; p["left"]=[-0.30,1.1,-0.2,0,0]; walk.put(p); time.sleep(0.6)
PY
python "$S/keys.py" $P >/dev/null; echo "3 fire: $(python "$S/hear.py" gm79-b 2>&1 | tail -1 | cut -c1-24)"
grep -a "breech: GM\|shell in\|reload: the GM\|NOTHING WENT\|fire: pull #[0-9]* bullets" "$L" | tail -8 | cut -c13-25,60-210
