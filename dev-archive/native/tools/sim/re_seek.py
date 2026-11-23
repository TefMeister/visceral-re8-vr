"""re_seek.py <joint> "<log text>" [span_cm=4] [lg|lt] -- RE2 / RE3: try places round a gun joint (re_go.py's way) until the game's
log shows the text; prints the offset that worked (cm: right, up, forward) and leaves the hand there. With `lg` / `lt` it presses
that button at each place (LG is let go between places); without, it only moves (a magazine brought to the well seats by itself)."""
import itertools, json, os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__)); py = sys.executable
GAME = os.environ["RV_GAME_DIR"]; LOG = os.path.join(GAME, "re2_framework_log.txt")
j, want = sys.argv[1], sys.argv[2]; span = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else 4
btn = "squeeze" if "lg" in sys.argv else "trigger" if "lt" in sys.argv else None
P = os.path.join(HERE, "pose_now.json")
def setp(**k):
    q = json.load(open(P)); q.update(k); json.dump(q, open(P, "w"))
offs = sorted(itertools.product((-span, 0, span, -2 * span, 2 * span), repeat=3), key=lambda o: sum(abs(c) for c in o))
for o in offs[:40]:
    if btn: setp(**{btn: 0.0}); time.sleep(0.25)
    m = os.path.getsize(LOG)
    subprocess.run([py, os.path.join(HERE, "re_go.py"), j] + [str(c) for c in o], capture_output=True)
    if btn: setp(**{btn: 1.0})
    time.sleep(0.8)
    with open(LOG, "rb") as f: f.seek(m); new = f.read().decode("utf-8", "replace")
    if want in new:
        print("worked at %+d %+d %+d cm from %s: %s" % (o[0], o[1], o[2], j, [l[l.find("visceral"):][:150] for l in new.splitlines() if want in l][0])); sys.exit(0)
print("not found in %d places" % min(40, len(offs))); sys.exit(1)
