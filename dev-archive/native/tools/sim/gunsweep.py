"""gunsweep.py <re2|re3> <wp> [<wp> ...]: with the game in play (zz_test_short2.lua installed, VR Bench on), for each gun:
give it, check it is in hand and that Hand Poser names it, pull the trigger until it is empty (fires?), pull once more
(the hammer click?). Prints one row per gun. Memory only: nothing is saved."""
import sys, os, time, json, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import walk
game = sys.argv[1]
ROOT = {"re2": r"C:\Steam\steamapps\common\RESIDENT EVIL 2  BIOHAZARD RE2", "re3": r"C:\Steam\steamapps\common\RE3"}[game]
LOG = os.path.join(ROOT, "re2_framework_log.txt"); REQ = os.path.join(ROOT, "reframework", "data", "zz_short.json")
STATE = os.path.join(ROOT, "reframework", "data", "hand_poser", "state.json")
P = {"right": [0.15, 1.45, -0.35, 90, 60], "left": [-0.30, 1.1, -0.2, 0, 0], "squeeze": 0.0, "trigger": 0.0, "rsqueeze": 0.0}
def since(n0):
    f = open(LOG, "rb"); f.seek(n0); return f.read().decode("utf-8", "replace")
def rt():
    import subprocess
    subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "vb.py"), "press", "right", "trigger", "0.12"], capture_output=True)
for wp in [int(a) for a in sys.argv[2:]]:
    row = {"wp": wp}
    n0 = os.path.getsize(LOG)
    json.dump({"gift": "WP%04d" % wp, "count": 1}, open(REQ, "w")); time.sleep(4.0)
    t = since(n0)
    m = re.findall(r"weapon: WP(\d+) ([^\r\n]*)", t)
    row["in hand"] = (m[-1][1].strip() if m and int(m[-1][0]) == wp else "NO (" + ("gift failed" if "failed" in t else (m[-1][1].strip() if m else "nothing")) + ")")
    if not row["in hand"].startswith("NO"):
        walk.put(P); time.sleep(0.6)
        try: row["hand poser"] = json.load(open(STATE)).get("gun", "?")
        except Exception: row["hand poser"] = "?"
        shots, empty, n1 = 0, False, os.path.getsize(LOG)
        for k in range(30):
            n2 = os.path.getsize(LOG); rt(); time.sleep(0.45); s = since(n2)
            if "EMPTY gun" in s or "bullets 0 -> 0" in s: empty = True; break
            if re.search(r"bullets (\d+) -> (\d+)", s): shots += 1
        row["fired"] = shots
        row["empty reached"] = empty
        n3 = os.path.getsize(LOG); rt(); time.sleep(0.6); s = since(n3)
        row["hammer"] = "yes" if "played dry_hammer" in s else ("muted/none" if empty else "-")
    print(json.dumps(row), flush=True)
