"""magseek2.py: RE2 test hand. Walks the left hand towards where RE2 says the magazine dock is (its 'the hand X m from'
line on each LG press), coordinate by coordinate, until it docks. Prints the spot."""
import sys, os, time, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import walk
LOG = r"C:\Steam\steamapps\common\RESIDENT EVIL 2  BIOHAZARD RE2\re2_framework_log.txt"
base = {"right": [0.12, 1.45, -0.42, 90, 35], "left": [-0.30, 1.1, -0.2, 0, 0], "squeeze": 0.0, "trigger": 0.0, "rsqueeze": 0.0}
def tryat(l, keep=False):
    p = dict(base); p["left"] = list(l) + [0, 0]; walk.put(p); time.sleep(0.35)
    n0 = os.path.getsize(LOG); p["squeeze"] = 1.0; walk.put(p); time.sleep(0.35)
    f = open(LOG, "rb"); f.seek(n0); s = f.read().decode("utf-8", "replace")
    if not keep: p["squeeze"] = 0.0; walk.put(p); time.sleep(0.25)
    m = re.search(r"the hand ([0-9.]+) m from", s)
    return (float(m.group(1)) if m else 9.0), ("docked on the magazine" in s)
l = [float(v) for v in sys.argv[1:4]]
d, ok = tryat(l)
step = 0.04
while step >= 0.005 and not ok:
    moved = False
    for i in range(3):
        for sgn in (1, -1):
            t = list(l); t[i] = round(t[i] + sgn * step, 3)
            dt, okt = tryat(t)
            if okt or dt < d: l, d, ok, moved = t, dt, okt, True; break
        if ok: break
    if not moved: step /= 2
print("spot", l, "dist", d, "docked", ok)
if ok: tryat(l, keep=True); print("held")
