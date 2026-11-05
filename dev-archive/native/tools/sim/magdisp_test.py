"""magdisp_test.py -- the magazine's look follows its own rounds, on the OpenXR Simulator through VR Bench (2026-11-05).
After village_sim_boot.py. LEMI: fire it empty (the game's own parts pattern at 2 / 1 / 0 loaded is logged), right B drops the
empty magazine (EMPTY look, the thrown copy too), a fresh one from the pouch (FULL look while the gun says 0), to the well (it
seats; the game's look again), then LG on the magazine + right B releases it into the hand with its rounds (FULL), one shot
(the chambered round; the hand's magazine must STAY full), LT at the well puts it back. Prints the plugin's log lines per step."""
import os, re, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import walk

G = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
DATA = os.path.join(G, "reframework", "data")
LOG = os.path.join(G, "re2_framework_log.txt")
WANT = re.compile(r"magdisp|reload: |magthrow\].*(copy shows|came to rest|copy made)")
POUCH = [-0.20, 1.08, -0.02, 0, 0]
GUN = [0.15, 1.35, -0.30, 0, 35]
AWAY = [-0.30, 1.1, -0.2, 0, 0]
pos = [os.path.getsize(LOG)]


def news(title):
    with open(LOG, "rb") as f:
        f.seek(pos[0]); data = f.read(); pos[0] += len(data)
    print(f"--- {title}")
    for line in data.decode("utf-8", "replace").splitlines():
        if WANT.search(line) and "skipped (#" not in line:
            print("  " + line.split("] ", 2)[-1][:230])


def pose(left=None, squeeze=None, trigger=None, rtrigger=None, rb=None):
    p = walk.load(); p["right"] = GUN
    if left is not None: p["left"] = list(left)
    if squeeze is not None: p["squeeze"] = squeeze
    if trigger is not None: p["trigger"] = trigger
    p["rtrigger"] = rtrigger if rtrigger is not None else 0.0
    p["rb"] = bool(rb)
    walk.put(p)


def w(*a):
    return subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), *a], capture_output=True, text=True).stdout.strip()


def equip(gun):
    open(os.path.join(DATA, "finger_rec", "command.txt"), "w").write(f"equip {gun}\n")
    time.sleep(5)


def main():
    equip("ri3046"); pose(AWAY, 0, 0); time.sleep(1.5); news("LEMI out")
    for k in range(14):   # fire it empty: one pull, let go
        pose(AWAY, rtrigger=1.0); time.sleep(0.15); pose(AWAY, rtrigger=0.0); time.sleep(0.45)
    time.sleep(1.5); news("fired until empty (the game's own look at 2 / 1 / 0)")
    # where the seated magazine is, found while it is seated (the zone is published only then): the well for later
    print(w("mag")); well = list(walk.load()["left"]); pose(AWAY, 0); time.sleep(1.0); news("the well found at %s" % [round(v, 2) for v in well[:3]])
    pose(AWAY, rb=True); time.sleep(0.25); pose(AWAY, rb=False); time.sleep(4.0)
    news("right B: the empty magazine out of the magwell")
    pose(POUCH, 0); time.sleep(0.8); pose(POUCH, 1.0); time.sleep(2.0)
    news("LG in the pouch: a fresh magazine in the hand (the gun says 0)")
    pause = float(os.environ.get("PAUSE", "0"))
    if pause: time.sleep(pause)
    pose(well, 1.0); time.sleep(3.5)
    news("brought to the well with LG held (a pouch magazine seats by itself)")
    pose(AWAY, 0); time.sleep(1.5); news("hand away")
    pose(well, 1.0); time.sleep(1.2)
    pose(well, 1.0, rb=True); time.sleep(0.25); pose(well, 1.0, rb=False); time.sleep(2.0)
    news("LG on the seated magazine + right B: released into the hand with its rounds")
    pose(well, 1.0, rtrigger=1.0); time.sleep(0.15); pose(well, 1.0, rtrigger=0.0); time.sleep(2.5)
    news("one shot with the magazine in the hand (the gun says 0 now; the hand's magazine must stay FULL)")
    if pause: time.sleep(pause)
    pose(well, 1.0, trigger=1.0); time.sleep(0.4); pose(well, 1.0, trigger=0.0); time.sleep(2.5)
    news("LT at the well: back in")
    pose(AWAY, 0); time.sleep(1.0); news("end")


if __name__ == "__main__":
    main()
