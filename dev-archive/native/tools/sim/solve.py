"""solve.py point=x,y,z ... vars=J.a,J.a,... [side=L] [rounds=3] -- pose fingers by numbers THROUGH the Hand Poser window (2026-11-23):
moves the named joint angles (pose.py names, e.g. T1.x,T1.y,T1.z,T2.y,T3.y) until the named points of the hand sit at the wanted
places in the WRIST's frame (cm; q_wrist.lua's numbers: x toward the fingers, -y out of the palm, +z the thumb's side).
Points: a joint (Thumb3, IndexF2 ...) or its fingertip (Thumbtip, Indextip, Middletip, Ringtip, Pinkytip). A point may get a weight:
Thumbtip=9,-4.5,6.6,2. Coordinate search, steps 12 / 6 / 3 / 1.5 degrees; prints the error (cm, root mean square) and the angles kept."""
import json, os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__)); py = sys.executable
GAME = os.environ.get("RV_GAME_DIR", r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE")
targets, vars_, rounds, side = {}, [], 4, "L"
for a in sys.argv[1:]:
    k, v = a.split("=")
    if k == "vars": vars_ = v.split(",")
    elif k == "rounds": rounds = int(v)
    elif k == "side": side = v
    else:
        f = [float(x) for x in v.split(",")]; targets[k] = (f[0:3], f[3] if len(f) > 3 else 1.0)
F = {"I": "IndexF", "M": "MiddleF", "R": "RingF", "P": "PinkyF", "T": "Thumb"}
def full(k):
    j, ax = k.split("."); return side + "_" + F[j[0]] + j[1], "xyz".index(ax)
def shape():
    # SOLVE_Q=q_gunframe.lua: the points in the GUN's frame instead of the wrist's (a thumb onto a latch, a hammer)
    o = subprocess.run([py, os.path.join(HERE, "rv.py"), "-f", os.path.join(HERE, os.environ.get("SOLVE_Q", "q_wrist.lua"))], capture_output=True, text=True).stdout
    d = {}
    for l in o.splitlines():
        if l.startswith("gun "): continue
        p = l.split()
        if len(p) >= 4:
            d[p[0]] = [float(x) for x in p[1:4]]
            if "tip" in p: i = p.index("tip"); d[p[0][:-1].replace("F", "") + "tip"] = [float(x) for x in p[i + 1:i + 4]]
    return d
def err(d):
    s, n = 0.0, 0.0
    for k, (t, w) in targets.items():
        if k not in d: print("no point", k, "have", sorted(d)); sys.exit(1)
        s += w * sum((d[k][i] - t[i]) ** 2 for i in range(3)); n += w
    return (s / n) ** 0.5
st = json.load(open(os.path.join(GAME, "reframework", "data", "hand_poser", "state.json")))["angles"]
if any(full(v)[0] not in st for v in vars_):   # the window is not reading these joints yet (no row): a harmless set makes the rows
    print("joints not in the window yet: send them once with pose.py / rcopy.py first: %s" % sorted({full(v)[0] for v in vars_ if full(v)[0] not in st})); sys.exit(1)
ang = {v: st[full(v)[0]][full(v)[1]] for v in vars_}
def put(a):
    if os.environ.get("RV_SIDE"): pass
    subprocess.run([py, os.path.join(HERE, "pose.py")] + ["%s%s=%.2f" % ("r" if side == "R" else "", k, x) for k, x in a.items()], capture_output=True)
    time.sleep(0.55)
put(ang); best = err(shape()); print("start %.2f cm" % best)
for step in (12.0, 6.0, 3.0, 1.5)[:rounds]:
    for v in vars_:
        for sgn in (1, -1):
            moved = False
            while True:
                t = dict(ang); t[v] += sgn * step; put(t); e = err(shape())
                if e < best - 0.02: best, ang, moved = e, t, True
                else: break
            if moved: break
    print("step %4.1f: %.2f cm" % (step, best))
put(ang); d = shape()
print("kept: " + " ".join("%s=%.1f" % (k, x) for k, x in ang.items()))
for k, (t, w) in targets.items(): print("  %-10s at %s (wanted %s)" % (k, " ".join("%.1f" % c for c in d[k]), " ".join("%.1f" % c for c in t)))
