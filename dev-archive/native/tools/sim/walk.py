"""walk.py <zone key> [start lx ly lz] -- move the left controller (VR Bench) until the game says the hand is closest to
that zone. The right controller stays at RIGHT. Reads zones_state.json hand_cm (the game writes it 4x a second).
Prints the best room position and distance; leaves the left hand there. Also: walk.py squeeze <0|1> keeps the pose."""
import sys, os, json, time
sys.path.insert(0, os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"))
import vb_input as I, vb_settings as S
STATE = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE\reframework\data\visceral_re8\zones_state.json"
POSE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pose_now.json")
RIGHT = [0.15, 1.35, -0.30, 0, 35]
def save(p): json.dump(p, open(POSE_FILE, "w"))
def load():
    try: return json.load(open(POSE_FILE))
    except Exception: return {"right": RIGHT, "left": [-0.30, 1.1, -0.2, 0, 0], "squeeze": 0.0, "trigger": 0.0}
def put(p):
    inp = I.Input().mode(poses="set", buttons="set")
    r = I.pose_from_ypr(p["right"][0:3], p["right"][3], p["right"][4]); inp.hand(S.HAND_RIGHT, grip=r, aim=r)
    l = I.pose_from_ypr(p["left"][0:3], p["left"][3], p["left"][4])
    inp.hand(S.HAND_LEFT, grip=l, aim=l, squeeze=p.get("squeeze", 0.0), trigger=p.get("trigger", 0.0))
    if p.get("rsqueeze") is not None: inp.hand(S.HAND_RIGHT, squeeze=p["rsqueeze"])
    if p.get("rb"): inp.hand(S.HAND_RIGHT, b=True)   # right B held, without letting go of LG (vb.py press resets the hands)
    I.write(inp); save(p)
def hand_cm(key):
    t0 = time.time()
    time.sleep(0.35)
    for _ in range(20):
        try:
            d = json.load(open(STATE))
            if d.get("t", 0) >= int(t0):
                for z in d.get("zones", []):
                    if z.get("key") == key and "hand_cm" in z: return z["hand_cm"]
                return None
        except Exception: pass
        time.sleep(0.1)
    return None
if __name__ == "__main__":
    p = load()
    if sys.argv[1] in ("squeeze", "trigger", "rsqueeze", "rb"):
        p[sys.argv[1]] = float(sys.argv[2]); put(p); print(sys.argv[1], sys.argv[2]); sys.exit()
    if sys.argv[1] == "set":   # set left x y z yaw pitch
        p["left"] = [float(v) for v in sys.argv[2:7]]; put(p); print("left at", p["left"]); sys.exit()
    key = sys.argv[1]
    if len(sys.argv) >= 5: p["left"] = [float(v) for v in sys.argv[2:5]] + p["left"][3:5]
    put(p); best = hand_cm(key)
    if best is None: print("no hand_cm for", key); sys.exit(1)
    step = 0.08
    while step >= 0.005:
        improved = False
        for ax in range(3):
            for sgn in (1, -1):
                q = dict(p); q["left"] = list(p["left"]); q["left"][ax] += sgn * step
                put(q); d = hand_cm(key)
                if d is not None and d < best - 0.2: best, p, improved = d, q, True; break
        if not improved: step /= 2
    put(p); print("best %.1f cm at left %s" % (best, [round(v, 3) for v in p["left"]]))
