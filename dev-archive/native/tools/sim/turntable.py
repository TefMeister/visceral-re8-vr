"""turntable.py <ri id> <zone> <out sheet> [lt] [long] [views=left,right,front,back,top,bottom] -- Tefa 2026-11-23: "can you also see
guns from straight on, barrel pointed towards the camera, from bottom view and top view, so you have a clear 360 look at the weapon
and all the hand poses on it": the gun turned six ways in front of the camera, each time with the named grip zone brought to the
middle of the picture (frame.py) and the left hand taken onto it with LG (`lt`: LG + LT). One sheet. The jacket should be off
(q_sleeve.lua). Needs keep.py and HV_HEAD. The zones themselves (where they start, end, overlap): zonemap.py."""
import json, subprocess, sys, time, os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import walk, hv
gun, zone, out = sys.argv[1:4]; fl = sys.argv[4:]; LT, LONG = "lt" in fl, "long" in fl
p0 = 90 if LONG else 55
VIEWS = {"left": (90, p0, 0), "right": (-90, p0, 0), "front": (180, p0, 0), "back": (0, p0, 0), "top": (90, p0, 80), "bottom": (90, p0, -75)}
want = ([a for a in fl if a.startswith("views=")] or ["views=left,right,front,back,top,bottom"])[0].split("=")[1].split(",")
GAME = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
P = os.path.join(HERE, "pose_now.json"); py = sys.executable
def setp(**k):
    q = json.load(open(P)); q.update(k); json.dump(q, open(P, "w"))
def zhv():
    t = subprocess.run([py, os.path.join(HERE, "rv.py"), "-f", os.path.join(HERE, "q_zonehv.lua")], capture_output=True, text=True).stdout
    return {l.split()[0]: [float(x) / 100.0 for x in l.split()[1:4]] for l in t.splitlines() if len(l.split()) == 4}
subprocess.run([py, os.path.join(HERE, "keys.py"), open(os.path.join(HERE, "pid.txt")).read().strip()], capture_output=True)
if int(json.load(open(walk.STATE)).get("gun", 0)) != int(gun[2:]):
    open(os.path.join(GAME, "reframework", "data", "finger_rec", "command.txt"), "w").write("equip " + gun); time.sleep(6)
PARK = hv.room(-0.30, -0.35, 0.25) + [hv.YAW, 0]; tiles = []
for v in want:
    y, p, r = VIEWS[v]
    setp(left=PARK, squeeze=0.0, trigger=0.0); time.sleep(0.5)
    subprocess.run([py, os.path.join(HERE, "frame.py"), zone, "yaw=%d" % y, "pitch=%d" % p, "roll=%d" % r, "at=" + os.environ.get("TURN_AT", "0.0,-0.02,0.36")], capture_output=True)
    z = zhv()
    if zone not in z: print(v, "zone not on"); continue
    zr = hv.room(*z[zone]); setp(left=[zr[0], zr[1] - 0.03, zr[2]] + [hv.YAW, 0]); time.sleep(0.6)
    subprocess.run([py, os.path.join(HERE, "walk.py"), zone], capture_output=True)
    setp(squeeze=1.0); time.sleep(1.1)
    if LT: setp(trigger=1.0); time.sleep(0.9)
    f = os.path.join(os.environ.get("TEMP", "."), "_turn_%s.png" % v)
    os.environ["SNAP_BOX"] = os.environ.get("STAGE_BOX", "0.15 0.1 0.85 0.9")
    print(subprocess.run([py, os.path.join(HERE, "snap.py"), f, "%s %s from the %s%s" % (gun, zone, v, " LG+LT" if LT else " LG")], capture_output=True, text=True).stdout.strip()); tiles.append(f)
if not os.environ.get("TURN_STAY"): setp(left=PARK, squeeze=0.0, trigger=0.0)   # TURN_STAY=1: the hand stays on the part after the last view (to pose it, then snap.py)
if tiles: subprocess.run([py, os.path.join(HERE, "sheet.py"), out, os.environ.get("TURN_COLS", str(min(len(tiles), 6)))] + tiles)   # one row per zone
