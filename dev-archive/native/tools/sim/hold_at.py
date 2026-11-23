"""hold_at.py <stage> [view=side|right|front|roll] -- bring the pistol in hand to one stage of the spare swap and STAY there
(LG held), so the pose can be set through Hand Poser and pictured: far (spare in hand, 14 cm under), docked, pull<percent>
(B pressed, the magazine that far out, e.g. pull50), out (both in hand), mag (plain: LG on the seated magazine, no spare),
magpull<percent> (plain: B, pulled). Needs keep.py, HV_HEAD. 2026-11-23."""
import json, subprocess, sys, time, os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import walk, hv
stage = sys.argv[1]; view = ([a for a in sys.argv[2:] if a.startswith("view=")] or ["view=right"])[0].split("=")[1]
P = os.path.join(HERE, "pose_now.json"); py = sys.executable
def setp(**k):
    q = json.load(open(P)); q.update(k); json.dump(q, open(P, "w"))
subprocess.run([py, os.path.join(HERE, "keys.py"), open(os.path.join(HERE, "pid.txt")).read().strip()], capture_output=True)
R = hv.room(0.05, 0.03, 0.32) + {"roll": [hv.YAW + 90, 55, -70], "right": [hv.YAW - 90, 55], "front": [hv.YAW + 180, 20], "side": [hv.YAW + 90, 55]}[view]
PARK = hv.room(-0.25, -0.30, 0.30) + [hv.YAW, 0]; POUCH = hv.room(-0.20, -0.62, 0.02) + [hv.YAW, 0]
setp(right=R, left=PARK, squeeze=0.0, trigger=0.0, rb=0, rsqueeze=None, rtrigger=0.0); time.sleep(0.8)
print(subprocess.run([py, os.path.join(HERE, "reseat.py")], capture_output=True, text=True).stdout.strip())
setp(right=R, left=PARK, squeeze=0.0, trigger=0.0, rb=0, rsqueeze=None, rtrigger=0.0); time.sleep(1.2)
print(subprocess.run([py, os.path.join(HERE, "walk.py"), "mag"], capture_output=True, text=True).stdout.strip().splitlines()[-1])
at = list(walk.load()["left"])
def down(cm): return [at[0], at[1] - cm / 100.0, at[2]] + at[3:]
plain = stage.startswith("mag")
if not plain: setp(left=POUCH); time.sleep(1.0); setp(squeeze=1.0); time.sleep(1.0)
if stage == "far": setp(left=down(14)); time.sleep(1.2); sys.exit()
setp(left=at); time.sleep(1.2)
if plain: setp(squeeze=1.0); time.sleep(1.0)
if stage in ("docked", "mag"): sys.exit()
setp(rb=1); time.sleep(0.4); setp(rb=0); time.sleep(0.8)
if "pull" in stage:
    pc = float(stage.split("pull")[1]); setp(left=down(9.0 * pc / 100.0 + 0.3)); time.sleep(1.0); sys.exit()
setp(left=down(14)); time.sleep(1.2)
