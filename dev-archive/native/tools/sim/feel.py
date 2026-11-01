"""feel.py "<log text>" [step_m] [span]: press LG at points around the left hand until the game log shows the text.
Leaves LG held at the first point that worked."""
import sys, os, time, itertools
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import walk
LOG = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE\re2_framework_log.txt"
want = sys.argv[1]; step = float(sys.argv[2]) if len(sys.argv) > 2 else 0.03; span = int(sys.argv[3]) if len(sys.argv) > 3 else 1
p = walk.load(); home = list(p["left"])
def log_size(): return os.path.getsize(LOG)
offs = sorted(itertools.product(range(-span, span + 1), repeat=3), key=lambda o: sum(abs(c) for c in o))
for o in offs:
    q = dict(p); q["left"] = [home[i] + o[i] * step for i in range(3)] + home[3:5]; q["squeeze"] = 0.0; walk.put(q); time.sleep(0.25)
    n0 = log_size(); q["squeeze"] = 1.0; walk.put(q); time.sleep(0.6)
    with open(LOG, "rb") as f: f.seek(n0); new = f.read().decode("utf-8", "replace")
    if want in new: print("worked at", [round(v, 3) for v in q["left"]]); sys.exit(0)
q = dict(p); q["squeeze"] = 0.0; walk.put(q); print("not found")
