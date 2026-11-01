"""survey.py: every Village gun, every grip zone: the sphere shows, the left hand walked in, LG pressed, what took the hand.
Needs: the game in play on the simulator, VR Bench on, zz_test_equip.lua installed, openrow.py running. Writes survey.txt."""
import sys, os, json, time, subprocess
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import walk
GAME = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
LOG = GAME + r"\re2_framework_log.txt"; DATA = GAME + r"\reframework\data\visceral_re8"
PID = open(os.path.join(HERE, "pid.txt")).read().strip()
GUNS = [("LEMI", 97158149), ("M1911", 2735256250), ("V61", 1157345091), ("USM-AI", 3132227914), ("S.T.A.K.E", 3875003266),
        ("Rocket Pistol", 2545563073), ("Samurai Edge", 949611560), ("M1851", 331140406), ("Handcannon", 634755339),
        ("W870", 2576167331 * 0 + 0), ("M1897", 0), ("F2", 0), ("WCX", 3003110346), ("Dragoon", 2146816802), ("SYG-12", 241847407),
        ("GM 79", 2576167331)]
KEYS = {"W870": "1", "M1897": "3", "F2": "4"}
TOOK = ["HAND ON", "too far", "docks there", "seated magazine", "the bolt takes it", "left-side sphere", "right-side sphere", "rack NEEDED"]
out = open(os.path.join(HERE, "survey.txt"), "w", encoding="utf-8")
def say(s): print(s, flush=True); out.write(s + "\n"); out.flush()
def front(): subprocess.run([sys.executable, os.path.join(HERE, "keys.py"), PID], capture_output=True)
def size(): return os.path.getsize(LOG)
def since(n0):
    with open(LOG, "rb") as f: f.seek(n0); return f.read().decode("utf-8", "replace")
def setopen(k): open(os.path.join(HERE, "openkey.txt"), "w").write(k)
REST = {"right": [0.12, 1.45, -0.42, 90, 35], "left": [-0.30, 1.1, -0.2, 0, 0], "squeeze": 0.0, "trigger": 0.0, "rsqueeze": 0.0}
for name, gid in GUNS:
    walk.put(dict(REST)); setopen(""); time.sleep(0.5)
    n0 = size()
    if name in KEYS: subprocess.run([sys.executable, os.path.join(HERE, "keys.py"), PID, KEYS[name]], capture_output=True)
    else:
        json.dump({"id": gid, "seq": int(time.time() * 1000)}, open(DATA + r"\test_equip.json", "w")); front()
    time.sleep(4.5); front()
    t = since(n0)
    pose = "pose loaded" if "own pose loaded" in t else "NO pose line"
    try: zs = [z for z in json.load(open(DATA + r"\zones_state.json"))["zones"] if z.get("on")]
    except Exception: zs = []
    say(f"== {name}: {pose}; zones {[z['key'] for z in zs]}")
    for z in zs:
        key = z["key"]; row = "part" if key in ("slide", "pump", "bolt") else key
        walk.put(dict(REST)); setopen(row); front(); n1 = size(); time.sleep(5.6)
        t = since(n1); shown = ("SHOWN" in t and f"WHERE {row}" in t)
        p = dict(REST); walk.save(p)
        r = subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), key, "0.0", "1.42", "-0.45"], capture_output=True, text=True, timeout=120)
        best = r.stdout.strip().splitlines()[-1] if r.stdout.strip() else "walk failed"
        front(); n2 = size(); walk.put(dict(walk.load(), squeeze=1.0)); time.sleep(1.5)
        lines = [l for l in since(n2).splitlines() if any(k in l for k in TOOK)]
        took = lines[-1].split("] ", 2)[-1][:150] if lines else "nothing took the hand"
        if not lines and key in ("handle", "drum", "insert"):   # the docks take the controller, a few cm from the drawn hand
            walk.put(dict(walk.load(), squeeze=0.0)); n3 = size()
            r = subprocess.run([sys.executable, os.path.join(HERE, "feel.py"), "docks there", "0.025", "2"], capture_output=True, text=True, timeout=200)
            lines = [l for l in since(n3).splitlines() if "docks there" in l]
            took = ("(felt) " + lines[-1].split("] ", 2)[-1][:150]) if lines else "nothing took the hand (felt too)"
        walk.put(dict(walk.load(), squeeze=0.0)); time.sleep(0.6)
        say(f"   {key:10s} sphere {'SHOWN' if shown else 'NOT SHOWN'}; {best}; LG: {took}")
setopen(""); walk.put(dict(REST)); say("done"); out.close()
