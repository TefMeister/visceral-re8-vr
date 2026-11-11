"""twomag_test.py -- two magazines in the left hand (src/twomag.h), on the OpenXR Simulator through VR Bench (2026-11-11).
After drive.sh, with the LEMI in hand (keys.py <pid> 2). Three shots, so the gun is not full; the seated magazine's place is
found (walk.py mag); LG at the pouch (a spare, the gun's still seated); LG held to the magazine (docks); right B (the gun's
magazine onto the grip's line); the hand drawn down the grip until it is out (two in the hand); LT (the swap: the spare goes
in by itself); LG let go (the old one drops). Prints the plugin's and the scripts' log lines per step.
    python twomag_test.py            the whole run
    python twomag_test.py spare      only: spare from the pouch, then LG let go (back in the pouch)"""
import os, re, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import subprocess
import walk

G = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
LOG = os.path.join(G, "re2_framework_log.txt")
WANT = re.compile(r"twomag|reload: |mag2\]|magthrow\].*(copy made|copy shows)")
POUCH = [-0.20, 1.08, -0.02, 0, 0]
GUN = [0.15, 1.35, -0.30, 0, 35]
AWAY = [-0.30, 1.1, -0.2, 0, 0]
pos = [os.path.getsize(LOG)]
seen = []


def news(title):
    with open(LOG, "rb") as f:
        f.seek(pos[0]); data = f.read(); pos[0] += len(data)
    print(f"--- {title}", flush=True)
    for line in data.decode("utf-8", "replace").splitlines():
        if WANT.search(line) and "skipped (#" not in line:
            t = line.split("] ", 2)[-1][:240]
            seen.append(t); print("  " + t, flush=True)


def front():   # the game pauses when its window is not in front, and then the hands do not move (2026-11-11: a whole run on stale poses)
    import ctypes
    u = ctypes.windll.user32
    h = u.FindWindowW(None, "Resident Evil Village")
    if h and u.GetForegroundWindow() != h:
        u.keybd_event(0x12, 0, 0, 0); u.SetForegroundWindow(h); u.keybd_event(0x12, 0, 2, 0)


def pose(left=None, squeeze=None, trigger=None, rtrigger=None, rb=None):
    front()
    p = walk.load(); p["right"] = GUN
    if left is not None: p["left"] = list(left)
    if squeeze is not None: p["squeeze"] = squeeze
    p["trigger"] = trigger if trigger is not None else 0.0
    p["rtrigger"] = rtrigger if rtrigger is not None else 0.0
    p["rb"] = bool(rb)
    walk.put(p)


def w(*a):
    front()
    return subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), *a], capture_output=True, text=True).stdout.strip()


def shot(name):   # SHOTS=<folder>: a picture of the game window at this step
    d = os.environ.get("SHOTS")
    if d: print("   ", subprocess.run([sys.executable, os.path.join(HERE, "shot.py"), os.path.join(d, name + ".png"), "0.8"], capture_output=True, text=True).stdout.strip()); front()


def has(text):
    return any(text in s for s in seen)


def main(mode):
    pose(AWAY, 0); time.sleep(1.5); news("start (the LEMI in hand)")
    for k in range(3):
        pose(AWAY, rtrigger=1.0); time.sleep(0.15); pose(AWAY, rtrigger=0.0); time.sleep(0.6)
    time.sleep(1.0); news("three shots (the gun is not full)")
    print(w("mag")); well = list(walk.load()["left"]); pose(AWAY, 0); time.sleep(1.0)
    news("the seated magazine found at %s" % [round(v, 2) for v in well[:3]])
    pose(POUCH, 0); time.sleep(0.8); pose(POUCH, 1.0); time.sleep(1.5)
    news("LG in the pouch with the magazine seated: a spare?")
    if os.environ.get("SHOTS"): pose([-0.10, 1.30, -0.35, 0, 0], 1.0); time.sleep(0.8); shot("spare")
    if mode == "spare":
        pose(AWAY, 1.0); time.sleep(1.0); pose(AWAY, 0); time.sleep(1.0); news("LG let go away from the gun: back in the pouch?")
        return
    pose(well, 1.0); time.sleep(1.5)
    news("LG held to the seated magazine: docked?")
    shot("docked")
    pose(well, 1.0, rb=True); time.sleep(0.25); pose(well, 1.0, rb=False); time.sleep(1.0)
    news("right B: the gun's magazine onto the grip's line?")
    # down the grip: the gun is pitched 35 degrees up, so its grip runs down and a little back; small steps, LG held
    here = list(well)
    for k in range(12):
        here[1] -= 0.02; here[2] += 0.008
        pose(here, 1.0); time.sleep(0.25)
        news("hand %.0f cm down the grip" % ((k + 1) * 2))
        if has("out of the bottom of the grip") or has("no rail"): break
    time.sleep(0.8); news("two in the hand?")
    shot("both")
    pose(here, 1.0, trigger=1.0); time.sleep(0.3); pose(here, 1.0, trigger=0.0); time.sleep(2.0)
    news("LT where the magazine came out: the swap?")
    if not has("the swap at"):   # refused as too far (on the simulator the drawn hand is far from its controller): walk the hand to the well
        print(w("well")); at = list(walk.load()["left"])
        pose(at, 1.0, trigger=1.0); time.sleep(0.3); pose(at, 1.0, trigger=0.0); time.sleep(2.0)
        news("LT with the hand walked to the well: the swap?")
    time.sleep(1.0)
    pose(AWAY, 1.0); time.sleep(1.2); news("hand away with LG still held (the old magazine stays?)")
    shot("old")
    pose(AWAY, 0); time.sleep(2.5); news("LG let go: the old magazine drops?")
    print("\nSUMMARY")
    for label, text in [("spare taken", "a spare magazine in the left hand"), ("docked with it", "a spare in it"),
                        ("B released the gun's magazine", "released (B)"), ("out into the hand", "out of the bottom of the grip"),
                        ("swap", "the swap at"), ("seated", "-> seated"), ("filled", "new magazine:"),
                        ("old dropped", "the old magazine gone from the hand"), ("spare drawn", "a spare magazine is drawn"),
                        ("old drawn", "role: the old magazine"), ("thrown copy", "copy made")]:
        print("  %-32s %s" % (label, "yes" if has(text) else "NO"))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "all")
