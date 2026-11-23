"""stages.py <ri id> <out sheet.png> [view=roll|side] -- a pistol's spare-magazine swap driven slowly, one picture per stage
(2026-11-23): spare from the pouch near the gun (19), docked under the seated magazine (17), B, the old magazine 15 / 50 / 90 %
down the grip (18, the pose follows the pull distance, bridge slot 279), out (16), LT and up: the spare home, the old one in hand (13).
Needs keep.py, HV_HEAD, Hand Poser open; hand_poser/blend_preview.json makes the blend show with the window open."""
import json, subprocess, sys, time, os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import walk, hv
gun, out = sys.argv[1], sys.argv[2]; view = (sys.argv[3:] or ["view=roll"])[0].split("=")[1]
GAME = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
P = os.path.join(HERE, "pose_now.json"); py = sys.executable
def rv(c): return subprocess.run([py, os.path.join(HERE, "rv.py"), c], capture_output=True, text=True).stdout.strip()
def setp(**k):
    q = json.load(open(P)); q.update(k); json.dump(q, open(P, "w"))
def slot(n):
    try: return float(rv("return _G.visceral_re8_bridge.r(%d)" % n))
    except Exception: return -1
tiles = []
def snap(label):
    f = os.path.join(os.environ.get("TEMP", "."), "_stage%d.png" % len(tiles))
    lab = "%s | spot %d u %.2f" % (label, slot(153), max(0.0, slot(279) - 1.0))
    os.environ["SNAP_BOX"] = os.environ.get("STAGE_BOX", "0.25 0.15 0.85 0.95")
    if os.environ.get("STAGE_PICS", "1") == "1": subprocess.run([py, os.path.join(HERE, "snap.py"), f, lab], capture_output=True); tiles.append(f)
    print(lab)
    if os.environ.get("STAGE_REL"): print(subprocess.run([py, os.path.join(HERE, "rv.py"), "-f", os.path.join(HERE, "q_rel.lua")], capture_output=True, text=True).stdout.rstrip())
subprocess.run([py, os.path.join(HERE, "keys.py"), open(os.path.join(HERE, "pid.txt")).read().strip()], capture_output=True)
num = int(gun[2:])
if int(json.load(open(walk.STATE)).get("gun", 0)) != num:
    open(os.path.join(GAME, "reframework", "data", "finger_rec", "command.txt"), "w").write("equip " + gun); time.sleep(5)
R = hv.room(0.05, 0.03, 0.32) + ([hv.YAW + 90, 55, -70] if view == "roll" else [hv.YAW - 90, 55] if view == "right" else [hv.YAW + 180, 20] if view == "front" else [hv.YAW + 90, 55])
PARK = hv.room(-0.25, -0.30, 0.30) + [hv.YAW, 0]; POUCH = hv.room(-0.20, -0.62, 0.02) + [hv.YAW, 0]
setp(right=R, left=PARK, squeeze=0.0, trigger=0.0, rb=0, rsqueeze=None, rtrigger=0.0); time.sleep(0.8)
print(subprocess.run([py, os.path.join(HERE, "reseat.py")], capture_output=True, text=True).stdout.strip())
setp(right=R, left=PARK, squeeze=0.0, trigger=0.0, rb=0, rsqueeze=None, rtrigger=0.0); time.sleep(1.0)
o = subprocess.run([py, os.path.join(HERE, "walk.py"), "mag"], capture_output=True, text=True).stdout.strip().splitlines()[-1]
at = list(walk.load()["left"]); print(o)
def down(cm): return [at[0], at[1] - cm / 100.0, at[2]] + at[3:]
setp(left=POUCH); time.sleep(1.0); setp(squeeze=1.0); time.sleep(1.0)
setp(left=down(14)); time.sleep(1.3); snap("spare, 14 cm under the gun")
setp(left=at); time.sleep(1.5); snap("docked")
setp(rb=1); time.sleep(0.4); setp(rb=0); time.sleep(0.8); snap("B pressed")
for cm in (1.5, 4.5, 8.0): setp(left=down(cm)); time.sleep(0.9); snap("pulled %.1f cm" % cm)
setp(left=down(14)); time.sleep(1.2); snap("out")
setp(trigger=1.0); time.sleep(0.4); setp(left=down(4)); time.sleep(0.8); snap("LT, spare going up")
setp(left=at); time.sleep(1.2); snap("spare home")
setp(trigger=0.0); time.sleep(0.4); setp(left=down(12)); time.sleep(1.2); snap("old magazine in hand")
setp(left=PARK); time.sleep(1.8); setp(squeeze=0.0); time.sleep(0.8)
if tiles: subprocess.run([py, os.path.join(HERE, "sheet.py"), out, os.environ.get("STAGE_COLS", "5")] + tiles)
