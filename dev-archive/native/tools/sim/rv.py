"""rv.py "<lua>" | rv.py -f file.lua  -- ask the running Village a question (zz_visceral_eval.lua must be in autorun).
Prints the answer. The chunk may return values; helpers S N T F M G C show, and the table E that stays between
questions. --front brings the game window forward first (the game pauses when it is not in front)."""
import json, os, sys, time, subprocess
GAME = os.environ.get("RV_GAME_DIR", r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE")   # RV_GAME_DIR: another RE Engine game with the eval script in autorun
D = os.path.join(GAME, "reframework", "data", "visceral_re8")
os.makedirs(D, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
front = "--front" in args
args = [a for a in args if a != "--front"]
code = open(args[1], encoding="utf-8").read() if args and args[0] == "-f" else " ".join(args)
if front:
    try:
        pid = open(os.path.join(HERE, "pid.txt")).read().strip()
        subprocess.run([sys.executable, os.path.join(HERE, "keys.py"), pid], capture_output=True)
    except Exception:
        pass
qid = int(time.time() * 1000) % 2000000000
tmp = os.path.join(D, "eval_in.json.tmp")
with open(tmp, "w", encoding="utf-8") as f:
    json.dump({"id": qid, "code": code}, f)
os.replace(tmp, os.path.join(D, "eval_in.json"))
t0 = time.time()
while time.time() - t0 < 12:
    try:
        with open(os.path.join(D, "eval_out.json"), encoding="utf-8") as f:
            a = json.load(f)
        if a.get("id") == qid:
            print(("" if a.get("ok") else "ERROR: ") + str(a.get("result", "")))
            sys.exit(0 if a.get("ok") else 1)
    except Exception:
        pass
    time.sleep(0.05)
print("NO ANSWER in 12 s (is the game running, in front, with zz_visceral_eval.lua in autorun?)")
sys.exit(2)
