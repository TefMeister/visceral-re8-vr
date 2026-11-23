"""keep.py [seconds] -- keeps walk.py's pose (pose_now.json) alive: rewritten every 10 ms with a 2 mm wobble, so the
sleeping-controller rule never drops the hands while walk.py / a picture is at work (2026-11-23). walk.py's own put()
writes once and saves; this loop picks every saved change up within 10 ms. Extra keys in pose_now.json:
  "right": [x y z yaw pitch (roll)], "left": the same, squeeze, trigger, rsqueeze, rtrigger, ra, rb, lx, ly (buttons, 0|1).
Stop: keep.py stop (or the seconds run out; default 3600)."""
import json, math, os, sys, time
sys.path.insert(0, os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"))
import vb_input as I, vb_settings as S

HERE = os.path.dirname(os.path.abspath(__file__))
POSE, STOP = os.path.join(HERE, "pose_now.json"), os.path.join(HERE, "keep.stop")
if len(sys.argv) > 1 and sys.argv[1] == "stop":
    open(STOP, "w").close(); sys.exit()
if os.path.exists(STOP): os.remove(STOP)
secs = float(sys.argv[1]) if len(sys.argv) > 1 else 3600.0
t0, p = time.time(), None
def pose(v, w):
    return I.pose_from_ypr([v[0] + w, v[1], v[2]], v[3], v[4], v[5] if len(v) > 5 else 0.0)
while time.time() - t0 < secs and not os.path.exists(STOP):
    try: p = json.load(open(POSE))
    except Exception: pass
    if p:
        w = 0.002 * math.sin((time.time() - t0) * 40.0)
        inp = I.Input().mode(poses="set", buttons="set")
        r, l = pose(p["right"], w), pose(p["left"], w)
        inp.hand(S.HAND_RIGHT, grip=r, aim=r, squeeze=p.get("rsqueeze"), trigger=p.get("rtrigger"),
                 a=bool(p.get("ra")) or None, b=bool(p.get("rb")) or None)
        inp.hand(S.HAND_LEFT, grip=l, aim=l, squeeze=p.get("squeeze", 0.0), trigger=p.get("trigger", 0.0),
                 x=bool(p.get("lx")) or None, y=bool(p.get("ly")) or None)
        I.write(inp)
    time.sleep(0.01)
