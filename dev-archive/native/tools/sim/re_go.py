"""re_go.py <joint> [dr du df] [keep=1] -- RE2 / RE3 (RV_GAME_DIR, HV_HEAD): move the LEFT controller until the drawn left wrist is at
the gun joint (q_re_parts.lua names: _01 slide / fore-end, _04 magazine ...; `pouch` = the left-hip pouch) plus an offset in cm in the
camera's frame (right, up, forward). Two corrections from what the game draws. Prints how far the wrist ended from the spot.
`right:<joint>` moves the RIGHT controller for the right wrist instead. 2026-11-23."""
import json, subprocess, sys, time, os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import hv
P = os.path.join(HERE, "pose_now.json"); py = sys.executable
a = [x for x in sys.argv[1:] if "=" not in x]; j = a[0]; off = [float(x) / 100 for x in a[1:4]] if len(a) >= 4 else [0, 0, 0]
hand, wrist = ("right", "r_arm_wrist") if j.startswith("right:") else ("left", "l_arm_wrist"); j = j.split(":")[-1]
def parts():
    t = subprocess.run([py, os.path.join(HERE, "rv.py"), "-f", os.path.join(HERE, "q_re_parts.lua")], capture_output=True, text=True).stdout
    return {l.split()[0]: [float(x) / 100 for x in l.split()[1:4]] for l in t.splitlines() if len(l.split()) == 4}
def setp(**k):
    q = json.load(open(P)); q.update(k); json.dump(q, open(P, "w"))
p = json.load(open(P)); ori = p[hand][3:]
if j == "pouch":
    setp(**{hand: hv.room(-0.20, -0.62, 0.02) + [hv.YAW, 0]}); time.sleep(0.9); print("at the pouch"); sys.exit()
z = parts()
if j not in z: print("no joint %s; have %s" % (j, sorted(z))); sys.exit(1)
want = [z[j][k] + off[k] for k in range(3)]; ctl = list(want)
for i in range(3):
    setp(**{hand: hv.room(*ctl) + ori}); time.sleep(0.7)
    z = parts(); want = [z[j][k] + off[k] for k in range(3)]; e = [want[k] - z[wrist][k] for k in range(3)]
    if max(abs(c) for c in e) < 0.012: break
    ctl = [ctl[k] + e[k] for k in range(3)]
print("wrist %.1f cm from %s%s" % (100 * sum(c * c for c in e) ** 0.5, j, (" %+d %+d %+d" % tuple(round(c * 100) for c in off)) if any(off) else ""))
