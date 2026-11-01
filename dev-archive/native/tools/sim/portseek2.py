"""portseek2.py x y z: RE2 test hand, a round already in the left hand (LG held): follows the 'round X m from the port'
log line until it goes in. Prints the spot."""
import sys, os, time, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import walk
LOG = r"C:\Steam\steamapps\common\RESIDENT EVIL 2  BIOHAZARD RE2\re2_framework_log.txt"
R = [0.15, 1.45, -0.35, 90, 60]
def tryat(l):
    p = {"right": R, "left": list(l) + [0, 0], "squeeze": 1.0, "trigger": 0.0, "rsqueeze": 0.0}
    n0 = os.path.getsize(LOG); walk.put(p); time.sleep(0.65)
    f = open(LOG, "rb"); f.seek(n0); s = f.read().decode("utf-8", "replace")
    m = re.findall(r"the round ([0-9.]+) m from the port", s)
    return (float(m[-1]) if m else 9.0), ("shell in:" in s)
l = [float(v) for v in sys.argv[1:4]]
d, ok = tryat(l); step = 0.08
while step >= 0.01 and not ok:
    moved = False
    for i in range(3):
        for sgn in (1, -1):
            t = list(l); t[i] = round(t[i] + sgn * step, 3)
            dt, okt = tryat(t)
            if okt or dt < d: l, d, ok, moved = t, dt, okt, True; break
        if ok: break
    if not moved: step /= 2
print("spot", l, "dist", d, "in", ok)
