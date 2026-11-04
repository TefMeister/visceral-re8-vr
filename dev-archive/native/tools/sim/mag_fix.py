"""mag_fix.py <gun id, e.g. ri3049> [--equip] [--apply] -- on the OpenXR Simulator: the gun in hand, the right controller level,
the left controller walked onto the magazine zone, LG pressed: read where the drawn palm lands against the magazine
(dockreport.cpp), and with --apply take that gap off the gun's magazine hold (dock_poses.json spot 4), then measure again.
--equip takes the gun out first (the finger recorder's `equip`). (2026-11-04, Opus; Tefa: "i need it to only land on the mag
and never the grip handle" ... "do the same for the other long guns too")"""
import json, os, re, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import walk

G = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
DATA = os.path.join(G, "reframework", "data")
LOG = os.path.join(G, "re2_framework_log.txt")
POSES = os.path.join(DATA, "visceral_re8", "dock_poses.json")
PAT = re.compile(r"dockreport: gun (\d+), the magazine: the palm sits ([\d.]+) cm from the part \(right ([-+\d.]+), up ([-+\d.]+), "
                 r"forward ([-+\d.]+) cm")


def hold_once():
    since = os.path.getsize(LOG)
    p = walk.load(); p["right"] = [0.10, 1.30, -0.35, 0, 90]; p["left"] = [0.10, 1.20, -0.38, 0, 90]; p["squeeze"] = 0.0; p["trigger"] = 0.0
    walk.put(p); time.sleep(0.8)
    r = subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), "mag"], capture_output=True, text=True)
    subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), "squeeze", "1"], capture_output=True)
    time.sleep(2.0)
    subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), "squeeze", "0"], capture_output=True)
    time.sleep(1.0)
    with open(LOG, "rb") as f:
        f.seek(since)
        text = f.read().decode("utf-8", "replace")
    m = list(PAT.finditer(text))
    took = "the left hand on the seated magazine" in text
    return (r.stdout.strip() or r.stderr.strip()[-160:]), took, (m[-1].groups() if m else None)


def main():
    gun = sys.argv[1]
    num = gun.replace("ri", "")
    if "--equip" in sys.argv:
        open(os.path.join(DATA, "finger_rec", "command.txt"), "w").write(f"equip {gun}\n")
        time.sleep(5)
    walked, took, g = hold_once()
    print(f"{gun}: walked ({walked}); LG took the magazine: {took}")
    if not g:
        print("  no measurement (LG did not take the magazine)"); return
    print(f"  palm {g[1]} cm from the magazine (right {g[2]}, up {g[3]}, toward the stock {g[4]})")
    if "--apply" not in sys.argv:
        return
    d = json.load(open(POSES, encoding="utf-8"))
    e = d.setdefault(num, {}).setdefault("4", {"x": 0, "y": 0, "z": 0, "rx": 0, "ry": 0, "rz": 0})
    before = dict(e)
    e["x"] = round(e.get("x", 0) - float(g[2]) / 100, 3)
    e["y"] = round(e.get("y", 0) - float(g[3]) / 100, 3)
    e["z"] = round(e.get("z", 0) - float(g[4]) / 100, 3)
    json.dump(d, open(POSES, "w", encoding="utf-8"), separators=(",", ":"))
    print(f"  hold shift {before.get('x')}, {before.get('y')}, {before.get('z')} -> {e['x']}, {e['y']}, {e['z']} m")
    time.sleep(1.5)   # the plugin re-reads dock_poses.json about once a second
    walked, took, g2 = hold_once()
    print(f"  again: LG took it: {took}; " + (f"palm {g2[1]} cm from the magazine (right {g2[2]}, up {g2[3]}, toward the stock {g2[4]})" if g2 else "no measurement"))


if __name__ == "__main__":
    main()
