"""rhand360.py <ri id> <out sheet> [long] [views=left,right,front,back,top,bottom] [rt=0..1] [b=1] -- the 360 view of the RIGHT hand on
the gun's grip (Tefa 2026-11-23: "right hand index finger on the trigger, right hand other 3 fingers gripping the handle"): the
gun hand held in the middle of the picture, close, turned six ways, the left hand away. rt= holds the trigger that far; b=1
presses right B once first (b=hold keeps it down) (the GM 79's latch, the Wolfsbane's cover). The jacket should be off. Needs keep.py, HV_HEAD."""
import json, subprocess, sys, time, os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import walk, hv
gun, out = sys.argv[1:3]; fl = sys.argv[3:]; LONG = "long" in fl
o = {a.split("=")[0]: a.split("=")[1] for a in fl if "=" in a}
p0 = 90 if LONG else 55
VIEWS = {"left": (90, p0, 0), "right": (-90, p0, 0), "front": (180, p0, 0), "back": (0, p0, 0), "top": (90, p0, 80), "bottom": (90, p0, -75)}
want = o.get("views", "left,right,front,back,top,bottom").split(",")
GAME = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
P = os.path.join(HERE, "pose_now.json"); py = sys.executable
def setp(**k):
    q = json.load(open(P)); q.update(k); json.dump(q, open(P, "w"))
subprocess.run([py, os.path.join(HERE, "keys.py"), open(os.path.join(HERE, "pid.txt")).read().strip()], capture_output=True)
if int(json.load(open(walk.STATE)).get("gun", 0)) != int(gun[2:]):
    open(os.path.join(GAME, "reframework", "data", "finger_rec", "command.txt"), "w").write("equip " + gun); time.sleep(6)
setp(left=hv.room(-0.35, -0.40, 0.20) + [hv.YAW, 0], squeeze=0.0, trigger=0.0, rb=0, rtrigger=float(o.get("rt", 0)))
at = [float(x) for x in o.get("at", "0.0,-0.03,0.26").split(",")]; tiles = []
if o.get("b") == "1": setp(right=hv.room(*at) + [hv.YAW + 90, p0]); time.sleep(0.8); setp(rb=1); time.sleep(0.3); setp(rb=0); time.sleep(0.9)
if o.get("b") == "hold": setp(right=hv.room(*at) + [hv.YAW + 90, p0]); time.sleep(0.8); setp(rb=1); time.sleep(0.9)   # B kept down for every picture (the thumb on the GM 79's latch)
for v in want:
    y, p, r = VIEWS[v]
    setp(right=hv.room(*at) + [hv.YAW + y, p, r]); time.sleep(1.1)
    f = os.path.join(os.environ.get("TEMP", "."), "_rh_%s.png" % v)
    os.environ["SNAP_BOX"] = os.environ.get("STAGE_BOX", "0.25 0.15 0.75 0.85")
    print(subprocess.run([py, os.path.join(HERE, "snap.py"), f, "%s right hand from the %s%s" % (gun, v, (" RT %s" % o["rt"]) if "rt" in o else "")], capture_output=True, text=True).stdout.strip()); tiles.append(f)
setp(rtrigger=0.0)
if tiles: subprocess.run([py, os.path.join(HERE, "sheet.py"), out, "3"] + tiles)
