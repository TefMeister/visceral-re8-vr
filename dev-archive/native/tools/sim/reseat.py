"""reseat.py -- start clean (2026-11-23): LG and LT let go, and if the gun's magazine is not seated (no `mag` zone on), a magazine
from the pouch is pushed home with LT at the well. Prints what it found."""
import json, subprocess, sys, time, os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import walk, hv
P = os.path.join(HERE, "pose_now.json"); py = sys.executable
def setp(**k):
    q = json.load(open(P)); q.update(k); json.dump(q, open(P, "w"))
def zones():
    try: return {z["key"] for z in json.load(open(walk.STATE)).get("zones", []) if z.get("on")}
    except Exception: return set()
subprocess.run([py, os.path.join(HERE, "keys.py"), open(os.path.join(HERE, "pid.txt")).read().strip()], capture_output=True)
PARK = hv.room(-0.25, -0.30, 0.30) + [hv.YAW, 0]; POUCH = hv.room(-0.20, -0.62, 0.02) + [hv.YAW, 0]
setp(left=PARK, squeeze=0.0, trigger=0.0, rb=0, rtrigger=0.0); time.sleep(1.5)
if "mag" in zones(): print("seated"); sys.exit()
o = subprocess.run([py, os.path.join(HERE, "walk.py"), "well"], capture_output=True, text=True).stdout.strip().splitlines()[-1]
at = list(walk.load()["left"])
setp(left=POUCH); time.sleep(1.0); setp(squeeze=1.0); time.sleep(1.0)
# the in / out test measures the MAGAZINE in the hand, not the controller: try places around the well until one seats it
for dy in (0.0, 0.03, -0.03, 0.06, -0.06, 0.09):
    for dx, dz in ((0, 0), (0.03, 0), (-0.03, 0), (0, 0.03), (0, -0.03)):
        setp(left=[at[0] + dx, at[1] + dy, at[2] + dz] + at[3:]); time.sleep(0.6)
        setp(trigger=1.0); time.sleep(0.5); setp(trigger=0.0); time.sleep(1.0)
        if "mag" in zones():
            setp(squeeze=0.0); time.sleep(0.6); setp(left=PARK); time.sleep(1.0)
            print("was out: a magazine pushed home at %+.0f %+.0f %+.0f cm from the well's best place" % (dx * 100, dy * 100, dz * 100)); sys.exit()
setp(squeeze=0.0); time.sleep(0.5); setp(left=PARK)
print("NOT SEATED; zones on: %s" % sorted(zones())); sys.exit(1)
