"""magthrow_test.py [pistol|rifle|both] -- the thrown magazine on the OpenXR Simulator (2026-11-05). After village_sim_boot.py.
pistol: the LEMI out, right B: the magazine drops out of the magwell (no speed) -> the copy should fall to the floor.
rifle:  the F2 out, the left hand onto its magazine (LG), LT pulls it into the hand, a quick swing forward and up, let go
        -> the copy should fly, tumble, land. Prints the plugin's and the script's log lines for each."""
import os, re, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import walk

G = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
DATA = os.path.join(G, "reframework", "data")
LOG = os.path.join(G, "re2_framework_log.txt")
WANT = re.compile(r"magthrow|throw copy|thrown copy|reload: drop|left grip let go|out of the magwell|magazine part")


def w(*a):
    return subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), *a], capture_output=True, text=True).stdout.strip()


def vb(*a):
    return subprocess.run([sys.executable, os.path.join(HERE, "vb.py"), *a], capture_output=True, text=True).stdout.strip()


def equip(gun):
    open(os.path.join(DATA, "finger_rec", "command.txt"), "w").write(f"equip {gun}\n")
    time.sleep(5)


def show_since(since, title):
    with open(LOG, "rb") as f:
        f.seek(since)
        text = f.read().decode("utf-8", "replace")
    print(f"--- {title}")
    for line in text.splitlines():
        if WANT.search(line):
            print("  " + line.split("] ", 2)[-1][:220])


def pistol():
    equip("ri3046")
    p = walk.load(); p["right"] = [0.15, 1.35, -0.30, 0, 35]; p["left"] = [-0.30, 1.1, -0.2, 0, 0]; p["squeeze"] = 0.0
    walk.put(p); time.sleep(1.0)
    since = os.path.getsize(LOG)
    print(vb("Resident Evil Village", "press", "b"))
    time.sleep(4.0)
    show_since(since, "pistol: right B")


def rifle():
    equip("ri3042")
    w("squeeze", "0"); time.sleep(1.0)
    p = walk.load(); p["right"] = [0.10, 1.30, -0.35, 0, 90]; p["left"] = [0.10, 1.20, -0.38, 0, 90]; walk.put(p); time.sleep(0.8)
    w("mag")
    since = os.path.getsize(LOG)
    w("squeeze", "1"); time.sleep(2.0)
    w("trigger", "1"); time.sleep(0.5); w("trigger", "0"); time.sleep(1.5)   # LT: the magazine into the hand
    # the swing: about 0.45 m forward and up over 0.15 s, then let go at the end of it
    p = walk.load()
    x, y, z = p["left"][0:3]
    for k in range(1, 7):
        p["left"][0:3] = [x, y + 0.04 * k, z - 0.07 * k]
        walk.put(p); time.sleep(0.025)
    p["squeeze"] = 0.0; walk.put(p)
    time.sleep(4.0)
    show_since(since, "rifle: out by hand, swung, let go")


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "both"
    if what in ("pistol", "both"): pistol()
    if what in ("rifle", "both"): rifle()
