"""dockscan.py "<log text>" [step_m] [n] -- from the left hand's place (put it on the zone with walk.py first), press LG at points
along each room axis (-n..+n steps) and print which presses made the game log the text: where the dock REALLY takes the hand,
against where its sphere is shown. Leaves the hand at home, LG up. 2026-11-23 (the Handcannon's drum took the hand only
3 cm above its shown middle)."""
import sys, os, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import walk
LOG = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE\re2_framework_log.txt"
want = sys.argv[1]; step = float(sys.argv[2]) if len(sys.argv) > 2 else 0.03; n = int(sys.argv[3]) if len(sys.argv) > 3 else 4
p = walk.load(); home = list(p["left"])
def press(at):
    q = dict(p); q["left"] = at + home[3:5]; q["squeeze"] = 0.0; walk.put(q); time.sleep(0.35)
    m = os.path.getsize(LOG); q["squeeze"] = 1.0; walk.put(q); time.sleep(0.45)
    with open(LOG, "rb") as f: f.seek(m); hit = want.encode() in f.read()
    q["squeeze"] = 0.0; walk.put(q); time.sleep(0.25); return hit
for ax, name in enumerate(("x", "y (up)", "z")):
    row = []
    for k in range(-n, n + 1):
        at = home[:3]; at[ax] += k * step; row.append("%+d:%s" % (round(k * step * 100), "Y" if press(at) else "."))
    print("room %-7s cm  %s" % (name, " ".join(row)))
q = dict(p); q["squeeze"] = 0.0; walk.put(q)
