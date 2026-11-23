"""blend_probe.py <ri id> <zone> <out sheet> [long] [view=side|right] -- do the left hand's pose changes BLEND? (2026-11-23, Tefa:
"animations blend from one to another"). Runs strokes.py on one zone (LG, LG + LT, pulled back, let go: its pictures are the
sheet) while q_blend.lua records every frame the left spot and how far the thumb, index and middle fingertips are from the wrist.
Then, for every change of spot: how much each finger moved in the 0.4 s after it, in how many frames, and the largest single
frame's share. "JUMP" = a change bigger than 1.5 cm written in ONE frame (not eased). Close the Hand Poser WINDOW first: while
it is open its own commands win and the ease is off (what a wearer sees has the window closed). Needs keep.py, HV_HEAD."""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__)); py = sys.executable
gun, zone, out = sys.argv[1], sys.argv[2], sys.argv[3]; rest = sys.argv[4:]
def rv(code): return subprocess.run([py, os.path.join(HERE, "rv.py"), code], capture_output=True, text=True).stdout.strip()
def rvf(f): return subprocess.run([py, os.path.join(HERE, "rv.py"), "-f", f], capture_output=True, text=True).stdout.strip()
rvf(os.path.join(HERE, "q_blend.lua"))
rv("E.blend_rec = false E.blend = {} E.blend_rec2 = true return 1")
r = subprocess.run([py, os.path.join(HERE, "strokes.py"), gun, out, "zones=" + zone] + rest, capture_output=True, text=True)
rv("E.blend_rec2 = false return 1")
rows = []
for l in rvf(os.path.join(HERE, "q_blend.lua")).splitlines():
    p = l.split()
    if len(p) == 6:
        try: rows.append([float(x) for x in p])
        except ValueError: pass
print("%d frames recorded over %.1f s" % (len(rows), rows[-1][0] - rows[0][0] if rows else 0))
NAMES = ("thumb", "index", "middle"); bad = 0
for i in range(1, len(rows)):
    if rows[i][1] == rows[i - 1][1]: continue
    t0 = rows[i][0]; seg = [rows[i - 1]] + [x for x in rows[i:] if x[0] - t0 <= 0.4]
    parts = []
    for k, nm in enumerate(NAMES):
        v = [x[3 + k] for x in seg]; tot = v[-1] - v[0]
        steps = [abs(v[j] - v[j - 1]) for j in range(1, len(v))]; big = max(steps) if steps else 0
        moving = sum(1 for s in steps if s > 0.05)
        # the ease is timed (Hand Poser POSE_BLEND_SEC 0.15 s, k = dt / 0.15 per frame, dt capped at 0.1): judge by TIME to 90 %, not
        # by the biggest frame (at the robot's 10-30 fps most of a change lands in the first frame however it is eased)
        t90 = next((x[0] - t0 for x in seg[1:] if abs(x[3 + k] - v[0]) >= 0.9 * abs(tot)), 0.0) if abs(tot) > 0.05 else 0.0
        flag = " JUMP" if abs(tot) > 1.5 and moving <= 1 else ""
        bad += bool(flag)
        parts.append("%s %+.1f cm, 90%% in %.2f s over %d frames%s" % (nm, tot, t90, moving, flag))
    print("%.2f s  spot %d%s -> %d%s: %s" % (t0 - rows[0][0], rows[i - 1][1] // 10, " LT" if rows[i - 1][1] % 10 else "", rows[i][1] // 10, " LT" if rows[i][1] % 10 else "", "; ".join(parts)))
print("JUMPS: %d" % bad)
print("strokes.py: " + " | ".join(l[:70] for l in r.stdout.strip().splitlines()[-3:]))
