"""re_move.py <cm> [steps] -- RE2 / RE3: slide the left controller <cm> along the gun's barrel (+ = toward the muzzle, - = back),
in small steps (q_re_parts.lua's fwd). `re_move.py down 10` moves it straight down instead."""
import json, subprocess, sys, time, os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import hv
P = os.path.join(HERE, "pose_now.json")
if sys.argv[1] in ("down", "up"):
    f = [0, -1 if sys.argv[1] == "down" else 1, 0]; d = float(sys.argv[2]) / 100; n = 6
else:
    t = subprocess.run([sys.executable, os.path.join(HERE, "rv.py"), "-f", os.path.join(HERE, "q_re_parts.lua")], capture_output=True, text=True).stdout
    f = [float(x) / 100 for x in [l for l in t.splitlines() if l.startswith("fwd ")][0].split()[1:4]]; d = float(sys.argv[1]) / 100; n = int(sys.argv[2]) if len(sys.argv) > 2 else 6
a, b = hv.room(*[c * d for c in f]), hv.room(0, 0, 0); dr = [a[k] - b[k] for k in range(3)]
p = json.load(open(P)); s = list(p["left"])
for i in range(1, n + 1):
    p["left"] = [s[k] + dr[k] * i / n for k in range(3)] + s[3:]; json.dump(p, open(P, "w")); time.sleep(0.1)
