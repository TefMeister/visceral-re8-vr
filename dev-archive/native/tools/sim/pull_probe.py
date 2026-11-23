"""pull_probe.py <ri id> [spare] [cm=16] [secs=3.2] -- the magazine's "pulling" stage, every frame (2026-11-23). A pistol in hand, magazine
seated (reseat.py), the left hand on it (walk.py mag), LG, then q_pull.lua starts recording bridge slots 279 (how far out) and 153
(the left hand's spot), B is pressed and the hand is taken straight down <cm> over <secs>. Prints the record and the mod's reload
lines. `spare`: a spare from the pouch first, docked on the seated magazine (the swap's 17 -> 18 -> 16). Needs keep.py and HV_HEAD; the sim folder's tools."""
import json, os, subprocess, sys, time
SIM = os.path.dirname(os.path.abspath(__file__))
HERE = SIM; sys.path.insert(0, SIM)
import walk, hv
gun = sys.argv[1]
kw = dict(a.split("=") for a in sys.argv[2:] if "=" in a)
CM, SECS = float(kw.get("cm", 16)), float(kw.get("secs", 3.2)); SPARE = "spare" in sys.argv[2:]
GAME = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
LOG = os.path.join(GAME, "re2_framework_log.txt")
P = os.path.join(SIM, "pose_now.json"); py = sys.executable
def setp(**k):
    q = json.load(open(P)); q.update(k); json.dump(q, open(P, "w"))
def rv(code): return subprocess.run([py, os.path.join(SIM, "rv.py"), code], capture_output=True, text=True).stdout.strip()
def rvf(f): return subprocess.run([py, os.path.join(SIM, "rv.py"), "-f", f], capture_output=True, text=True).stdout.strip()
def gun_now():
    try: return json.load(open(walk.STATE)).get("gun", 0)
    except Exception: return 0
subprocess.run([py, os.path.join(SIM, "keys.py"), open(os.path.join(SIM, "pid.txt")).read().strip()], capture_output=True)
R = hv.room(0.05, 0.03, 0.32) + [hv.YAW - 90, 55]
PARK = hv.room(-0.25, -0.30, 0.30) + [hv.YAW, 0]
POUCH = hv.room(-0.20, -0.62, 0.02) + [hv.YAW, 0]
setp(right=R, left=PARK, squeeze=0.0, trigger=0.0, rb=0, rsqueeze=None, rtrigger=0.0); time.sleep(0.8)
num = int(gun[2:])
if gun_now() != num:
    with open(os.path.join(GAME, "reframework", "data", "finger_rec", "command.txt"), "w") as f: f.write("equip " + gun)
    for _ in range(24):
        time.sleep(0.5)
        if gun_now() == num: break
    time.sleep(2.5)
if gun_now() != num: print("NOT IN HAND"); sys.exit(1)
print(subprocess.run([py, os.path.join(SIM, "reseat.py")], capture_output=True, text=True).stdout.strip())
setp(right=R, left=PARK, squeeze=0.0, trigger=0.0, rb=0); time.sleep(1.2)
print(subprocess.run([py, os.path.join(SIM, "walk.py"), "mag"], capture_output=True, text=True).stdout.strip().splitlines()[-1])
at = list(walk.load()["left"])
if SPARE:
    setp(left=POUCH); time.sleep(1.0); setp(squeeze=1.0); time.sleep(1.0); setp(left=at); time.sleep(1.3)
else:
    setp(squeeze=1.0); time.sleep(1.0)
rvf(os.path.join(HERE, "q_pull.lua"))
rv("E.pull = {} E.pull_last = nil E.pull_rec = true return 1")
mark = os.path.getsize(LOG); time.sleep(0.3)
t0 = time.time(); setp(rb=1); time.sleep(0.25); setp(rb=0); time.sleep(0.3)
n = max(8, int(SECS / 0.08)); marks = []
for i in range(1, n + 1):
    d = CM * i / n
    setp(left=[at[0], at[1] - d / 100.0, at[2]] + at[3:]); marks.append((time.time() - t0, d)); time.sleep(SECS / n)
time.sleep(1.0)
rv("E.pull_rec = false return 1")
print("== the record (time from the first frame recorded; B was pressed about 0.3 s in):")
print(rvf(os.path.join(HERE, "q_pull.lua")))
print("== the hand's way down (time from B, cm): " + ", ".join("%.2f:%.1f" % m for m in marks[:: max(1, n // 10)]))
with open(LOG, "rb") as f:
    f.seek(mark); txt = f.read().decode("utf-8", "replace")
print("== the mod's reload lines:")
for l in txt.splitlines():
    if "visceral-re8] reload:" in l and "refused" not in l: print("  " + l[l.find("reload:"):][:200])
setp(squeeze=0.0, trigger=0.0, left=PARK); time.sleep(0.5)
