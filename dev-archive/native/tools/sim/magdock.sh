# magdock.sh <ri id>: a long gun's seated magazine brought to the middle of the picture, the left hand docked on it with LG (stays).
S="$(cd "$(dirname "$0")" && pwd)"; cd "$S"; G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
python -c "
import json,sys; sys.path.insert(0,'.'); import walk
print(json.load(open(walk.STATE)).get('gun'))" | grep -q "${1#ri}" || { echo "equip $1" > "$G/reframework/data/finger_rec/command.txt"; sleep 6; }
python step.py left=-0.30,-0.35,0.25,0,0 squeeze=0 trigger=0 wait=0.5 >/dev/null; python reseat.py | tail -1; python frame.py mag yaw=${MAGDOCK_YAW:-90} pitch=90 at=0.0,0.02,0.40 >/dev/null
python - <<'PY'
import json,subprocess,sys
sys.path.insert(0,'.'); import hv
t=subprocess.run([sys.executable,"rv.py","-f","q_zonehv.lua"],capture_output=True,text=True).stdout
z={l.split()[0]:[float(x)/100 for x in l.split()[1:4]] for l in t.splitlines() if len(l.split())==4}["mag"]; zr=hv.room(*z)
p=json.load(open("pose_now.json")); p["left"]=[zr[0],zr[1]-0.04,zr[2],hv.YAW,0]; json.dump(p,open("pose_now.json","w"))
PY
sleep 0.6; python walk.py mag | tail -1 | cut -c1-50; python step.py squeeze=1 wait=1.2 | tail -1 | cut -c1-80
