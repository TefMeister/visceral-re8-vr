"""frame.py <zone> [yaw=90] [pitch=55] [roll=0] [at=r,u,f] -- Tefa 2026-11-23: "can you angle hands in front of the camera so you can
have a look at whatever angle you need for long guns and just in general": hold the gun turned yaw / pitch / roll (hv.py's
numbers: yaw 90 = pointing to the view's left, -90 right, 180 at the camera) and slide it until the named grip zone (mag, well,
slide, slide-left, bolt, pump, grip, handle, drum, insert) sits at `at` in the camera's view (m: right, up, forward; default
0,-0.03,0.27: the middle, close). Leaves the gun there; prints where every zone is (cm). Needs keep.py and HV_HEAD."""
import json, subprocess, sys, time, os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import hv
zone = sys.argv[1]; o = {"yaw": 90.0, "pitch": 55.0, "roll": 0.0, "at": "0,-0.03,0.27"}
for a in sys.argv[2:]: k, v = a.split("="); o[k] = v
at = [float(x) for x in o["at"].split(",")]; P = os.path.join(HERE, "pose_now.json"); py = sys.executable
def setp(**k):
    q = json.load(open(P)); q.update(k); json.dump(q, open(P, "w"))
def zones():
    t = subprocess.run([py, os.path.join(HERE, "rv.py"), "-f", os.path.join(HERE, "q_zonehv.lua")], capture_output=True, text=True).stdout
    return {l.split()[0]: [float(x) / 100.0 for x in l.split()[1:4]] for l in t.splitlines() if len(l.split()) == 4}
subprocess.run([py, os.path.join(HERE, "keys.py"), open(os.path.join(HERE, "pid.txt")).read().strip()], capture_output=True)
pos = [0.05, 0.0, 0.40]
ori = [hv.YAW + float(o["yaw"]), float(o["pitch"]), float(o["roll"])]
for i in range(4):
    setp(right=hv.room(*pos) + ori); time.sleep(1.0)
    z = zones()
    if zone not in z: print("zone %s is not on; on: %s" % (zone, sorted(z))); sys.exit(1)
    e = [at[k] - z[zone][k] for k in range(3)]
    if max(abs(c) for c in e) < 0.01: break
    pos = [pos[k] + e[k] for k in range(3)]
print("gun held at hv %s; zones (cm, right up forward): %s" % (",".join("%.3f" % c for c in pos), "  ".join("%s %s" % (k, ",".join("%.0f" % (c * 100) for c in v)) for k, v in z.items())))
