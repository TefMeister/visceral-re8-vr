"""strokes.py <ri id> <out sheet> [long] [view=side|right|front] [zones=slide,slide-left] -- the racking hand pictured (2026-11-23):
for each stroke zone that is on (slide, slide-left, pump, bolt, handle, hammer, drum): LG (ready on it), LG + LT, pulled back, let go.
The jacket should be hidden (q_sleeve.lua). Needs keep.py, HV_HEAD."""
import json, subprocess, sys, time, os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import walk, hv
gun, out = sys.argv[1], sys.argv[2]; fl = sys.argv[3:]; LONG = "long" in fl
view = ([a for a in fl if a.startswith("view=")] or ["view=side"])[0].split("=")[1]
want = ([a for a in fl if a.startswith("zones=")] or ["zones=slide,slide-left,pump,bolt,handle,hammer,drum"])[0].split("=")[1].split(",")
GAME = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
P = os.path.join(HERE, "pose_now.json"); py = sys.executable
def setp(**k):
    q = json.load(open(P)); q.update(k); json.dump(q, open(P, "w"))
def zones():
    d = json.load(open(walk.STATE)); return [z["key"] for z in d.get("zones", []) if z.get("on")], d.get("gun", 0), d.get("spot")
tiles = []
def snap(label):
    f = os.path.join(os.environ.get("TEMP", "."), "_stroke%d.png" % len(tiles))
    os.environ["SNAP_BOX"] = os.environ.get("STAGE_BOX", "0.0 0.0 1.0 1.0")
    print(subprocess.run([py, os.path.join(HERE, "snap.py"), f, label], capture_output=True, text=True).stdout.strip()); tiles.append(f)
subprocess.run([py, os.path.join(HERE, "keys.py"), open(os.path.join(HERE, "pid.txt")).read().strip()], capture_output=True)
if int(zones()[1]) != int(gun[2:]):
    open(os.path.join(GAME, "reframework", "data", "finger_rec", "command.txt"), "w").write("equip " + gun); time.sleep(6)
yaw = {"side": 90, "right": -90, "front": 180}[view]
R = (hv.room(0.30 if view == "side" else -0.30, 0.0, 0.70) + [hv.YAW + yaw, 90]) if LONG else (hv.room(0.05, 0.03, 0.32) + [hv.YAW + yaw, 55])
PARK = hv.room(-0.25, -0.30, 0.30) + [hv.YAW, 0]; START = hv.room(-0.02, -0.10, 0.30) if not LONG else hv.room(-0.05, -0.10, 0.60)
back = (hv.RX, 0.0, hv.RZ) if view == "side" else (-hv.RX, 0.0, -hv.RZ)   # the gun points to the view's left (side) or right
setp(right=R, left=PARK, squeeze=0.0, trigger=0.0, rb=0, rsqueeze=None, rtrigger=0.0); time.sleep(1.2)
for key in [k for k in zones()[0] if k in want]:
    setp(left=START + [hv.YAW, 0], squeeze=0.0, trigger=0.0); time.sleep(0.5)
    o = subprocess.run([py, os.path.join(HERE, "walk.py"), key], capture_output=True, text=True).stdout.strip().splitlines()[-1]
    if not o.startswith("best"): print(key, o); continue
    at = list(walk.load()["left"])
    setp(squeeze=1.0); time.sleep(1.2); snap("%s LG" % key)
    setp(trigger=1.0); time.sleep(0.9); snap("%s LG+LT" % key)
    d = 0.18 if key == "pump" else 0.10
    for i in range(1, 7): setp(left=[at[0] + back[0] * d * i / 6, at[1], at[2] + back[2] * d * i / 6] + at[3:]); time.sleep(0.12)
    time.sleep(0.8); snap("%s pulled back" % key)
    setp(left=at); time.sleep(0.6); setp(trigger=0.0); time.sleep(0.3); setp(squeeze=0.0); time.sleep(0.6)
setp(left=PARK)
if tiles: subprocess.run([py, os.path.join(HERE, "sheet.py"), out, os.environ.get("STAGE_COLS", "3")] + tiles)
