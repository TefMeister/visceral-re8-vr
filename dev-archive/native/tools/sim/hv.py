"""hv.py key=value ... -- set walk.py's pose in HEAD-VIEW numbers (the real headset on the desk, 2026-11-23):
right=r,u,f,yaw,pitch left=r,u,f,yaw,pitch (metres right / up / forward of the headset; yaw relative to where it looks,
+ = turned left) and squeeze= trigger= rsqueeze= rtrigger= rb= ra= lx= ly= (0..1). HV_HEAD="x y z fx fz" overrides the head."""
import json, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
H = [float(v) for v in os.environ.get("HV_HEAD", "0.28 -0.39 -0.68 0.70 0.71").split()]
hx, hy, hz, fx, fz = H; n = math.hypot(fx, fz); fx, fz = fx / n, fz / n; RX, RZ = -fz, fx
YAW = math.degrees(math.atan2(-fx, -fz))
def room(r, u, f): return [hx + RX * r + fx * f, hy + u, hz + RZ * r + fz * f]
if __name__ == "__main__":
    P = os.path.join(HERE, "pose_now.json"); p = json.load(open(P))
    for a in sys.argv[1:]:
        k, v = a.split("="); v = [float(x) for x in v.split(",")]
        if k in ("right", "left"): p[k] = room(*v[0:3]) + [YAW + v[3], v[4]] + v[5:6]
        else: p[k] = v[0]
    json.dump(p, open(P, "w"))
