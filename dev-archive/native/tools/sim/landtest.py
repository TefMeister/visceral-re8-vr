"""landtest.py <ri id> [long] [zones=mag,slide,grip] -- does the left hand land on the part aimed at? (2026-11-23, Tefa: "hands land
where they should with LG"; whichpart.cpp.) For each grip zone named (default: every one that is on, without well / hand): the
left controller comes to the zone's MIDDLE from three sides (from the left, from below, from the front; 12 cm out, LG up), LG is
pressed, and the spot the game gives is read (Hand Poser's state: the pose name). One line per try, and PASS / FAIL per zone
(mag wants spot 4; slide / bolt / pump want 3 or 8; grip wants neither). Needs keep.py and HV_HEAD."""
import json, os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import walk, hv
gun = sys.argv[1]; fl = sys.argv[2:]; LONG = "long" in fl
GAME = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
P = os.path.join(HERE, "pose_now.json"); py = sys.executable
WANT = {"mag": (4,), "slide": (3, 8, 11, 12), "slide-left": (8, 3, 12, 11), "bolt": (3, 8, 11, 12), "pump": (3, 5, 11), "handle": (5, 10), "drum": (6,), "insert": (7,)}
def setp(**k):
    q = json.load(open(P)); q.update(k); json.dump(q, open(P, "w"))
def zhv():
    t = subprocess.run([py, os.path.join(HERE, "rv.py"), "-f", os.path.join(HERE, "q_zonehv.lua")], capture_output=True, text=True).stdout
    return {l.split()[0]: [float(x) / 100.0 for x in l.split()[1:4]] for l in t.splitlines() if len(l.split()) == 4}
def spot():
    try: s = json.load(open(walk.STATE)).get("spot")
    except Exception: s = None
    try: n = json.load(open(os.path.join(GAME, "reframework", "data", "hand_poser", "state.json"))).get("spot", "?")
    except Exception: n = "?"
    return s, n
subprocess.run([py, os.path.join(HERE, "keys.py"), open(os.path.join(HERE, "pid.txt")).read().strip()], capture_output=True)
if int(json.load(open(walk.STATE)).get("gun", 0)) != int(gun[2:]):
    open(os.path.join(GAME, "reframework", "data", "finger_rec", "command.txt"), "w").write("equip " + gun); time.sleep(6)
PARK = hv.room(-0.30, -0.35, 0.25) + [hv.YAW, 0]
setp(left=PARK, squeeze=0.0, trigger=0.0); time.sleep(0.5)
first = "pump" if "pump" in zhv() else "mag"
subprocess.run([py, os.path.join(HERE, "frame.py"), first, "yaw=90", "pitch=%d" % (90 if LONG else 55), "roll=0", "at=0.0,-0.02,0.40"], capture_output=True)
z = zhv(); names = ([a for a in fl if a.startswith("zones=")] or ["zones=" + ",".join(k for k in z if k not in ("well", "hand"))])[0].split("=")[1].split(",")
SIDES = {"from the left": (-0.12, 0, 0), "from below": (0, -0.12, 0), "from the front": (0, 0, -0.12)}   # head view: right, up, forward (toward the camera = -forward)
bad = 0
for name in names:
    if name not in z: print("%-10s not on" % name); continue
    ok = 0
    for side, o in SIDES.items():
        z = zhv(); c = z[name]
        setp(left=hv.room(c[0] + o[0], c[1] + o[1], c[2] + o[2]) + [hv.YAW, 0], squeeze=0.0, trigger=0.0); time.sleep(0.7)
        for k in (0.5, 0.0):   # in two steps to the middle
            setp(left=hv.room(c[0] + o[0] * k, c[1] + o[1] * k, c[2] + o[2] * k) + [hv.YAW, 0]); time.sleep(0.35)
        setp(squeeze=1.0); time.sleep(1.2)
        s, n = spot(); good = (s in WANT[name]) if name in WANT else (s not in (3, 4, 8, 11, 12, 13))
        ok += good; print("%s %-10s %-15s -> spot %s '%s'  %s" % (gun, name, side, s, n, "ok" if good else "WRONG PART"))
        setp(squeeze=0.0); time.sleep(0.5); setp(left=PARK); time.sleep(0.5)
    print("%s %-10s %s (%d of 3)" % (gun, name, "PASS" if ok == 3 else "FAIL", ok)); bad += ok != 3
    # toward=0.3: also a press 30 % of the way from this zone's middle to each other zone's middle (still this part's side)
    T = ([a for a in fl if a.startswith("toward=")] or ["toward=0"])[0].split("=")[1]
    for other in ([k for k in names if k != name and k in z] if float(T) > 0 else []):
        z = zhv(); c, e = z[name], z[other]; q = [c[i] + (e[i] - c[i]) * float(T) for i in range(3)]
        setp(left=hv.room(q[0], q[1] - 0.10, q[2]) + [hv.YAW, 0], squeeze=0.0, trigger=0.0); time.sleep(0.7)
        setp(left=hv.room(*q) + [hv.YAW, 0]); time.sleep(0.5); setp(squeeze=1.0); time.sleep(1.2)
        s, n = spot(); good = (s in WANT[name]) if name in WANT else (s not in (3, 4, 8, 11, 12, 13))
        print("%s %-10s %s%% toward %-6s -> spot %s '%s'  %s" % (gun, name, int(float(T) * 100), other, s, n, "ok" if good else "WRONG PART")); bad += not good
        setp(squeeze=0.0); time.sleep(0.5); setp(left=PARK); time.sleep(0.5)
sys.exit(1 if bad else 0)
