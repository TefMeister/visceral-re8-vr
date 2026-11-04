"""mag_match.py <gun id, e.g. ri3049> -- make a plain LG press on a long gun's magazine land where the hand lands after a
re-insert (Tefa, 2026-11-04: "just take the mag out once and put it back, it lands on the right spot then"). On the OpenXR
Simulator: take the gun out (the finger recorder's `equip`), right controller level, left controller onto the magazine zone,
LG pressed: measure (A); LT: the magazine out into the hand; to the well, LT: back in, LG still held: measure (B); shift the
gun's magazine hold (dock_poses.json spot 4) by B - A; let go, press again: measure (C), which should match B.
F2 done this way 2026-11-04 23:5x (A 13.9 cm, B 21.9, after the shift both 21.6)."""
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


def w(*a):
    return subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), *a], capture_output=True, text=True).stdout.strip()


def tap_lt():
    w("trigger", "1"); time.sleep(0.5); w("trigger", "0")


def read_since(since, pat=PAT):
    with open(LOG, "rb") as f:
        f.seek(since)
        text = f.read().decode("utf-8", "replace")
    m = list(pat.finditer(text))
    return text, (tuple(float(x) for x in m[-1].groups()[2:5]) if m else None)


def press():
    w("squeeze", "0"); time.sleep(1.2)
    p = walk.load(); p["right"] = [0.10, 1.30, -0.35, 0, 90]; p["left"] = [0.10, 1.20, -0.38, 0, 90]; walk.put(p); time.sleep(0.8)
    w("mag")
    since = os.path.getsize(LOG)
    w("squeeze", "1"); time.sleep(2.0)
    text, g = read_since(since)
    return ("the left hand on the seated magazine" in text), g


def main():
    gun = sys.argv[1]
    num = gun.replace("ri", "")
    open(os.path.join(DATA, "finger_rec", "command.txt"), "w").write(f"equip {gun}\n")
    time.sleep(5)
    took, a = press()
    print(f"{gun}: press: took {took}, palm {a}")
    if not took or not a:
        w("squeeze", "0"); return
    since = os.path.getsize(LOG)
    tap_lt(); time.sleep(2.0)
    w("well"); time.sleep(0.5)
    tap_lt(); time.sleep(3.0)
    text, b = read_since(since)
    if "seated (seated)" not in text:   # sometimes the first LT lands before the hand is at the well: once more
        tap_lt(); time.sleep(3.0)
        text, b = read_since(since)
    print(f"  after the re-insert: seated {'seated (seated)' in text}, palm {b}")
    if not b or b == a:
        w("squeeze", "0"); return
    d = json.load(open(POSES, encoding="utf-8"))
    e = d.setdefault(num, {}).setdefault("4", {"x": 0, "y": 0, "z": 0, "rx": 0, "ry": 0, "rz": 0})
    before = (e.get("x", 0), e.get("y", 0), e.get("z", 0))
    e["x"] = round(before[0] + (b[0] - a[0]) / 100, 3)
    e["y"] = round(before[1] + (b[1] - a[1]) / 100, 3)
    e["z"] = round(before[2] + (b[2] - a[2]) / 100, 3)
    json.dump(d, open(POSES, "w", encoding="utf-8"), separators=(",", ":"))
    print(f"  hold shift {before} -> {(e['x'], e['y'], e['z'])} m")
    time.sleep(1.5)
    took, c = press()
    print(f"  press again: took {took}, palm {c} (want {b})")
    w("squeeze", "0")


if __name__ == "__main__":
    main()
