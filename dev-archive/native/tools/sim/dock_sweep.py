"""dock_sweep.py <quick-slot key> <zone> [<zone> ...] -- on the OpenXR Simulator, for one gun: draw it (number key), and for
each zone: walk the left controller to it (walk.py, by zones_state.json hand_cm), press LG, let the hold settle, read where
the drawn palm landed (dock_report.tsv, written by the plugin's dockreport.cpp), let go. Prints one line per zone and keeps
the side-view picture. Zones are the zones_state.json keys: mag, slide (= the pump / bolt / slide), slide-left, grip,
handle, drum, insert. (2026-11-04, Opus; Tefa: "making sure the hands actually land where they have to with LG")"""
import os, re, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import walk

G = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
REPORT = os.path.join(G, "reframework", "data", "visceral_re8", "dock_report.tsv")
NAMES = {"slide": "part (slide / pump / bolt)", "pump": "part (slide / pump / bolt)", "bolt": "part (slide / pump / bolt)", "slide-left": "slide from the left", "mag": "magazine", "handle": "handle",
         "drum": "drum", "insert": "breech", "grip": "front grip"}
# 2026-11-04 22:5x: the right controller LEVEL (pitch 90 = the gun level, learned on the scope job), low and ahead, so a
# camera beside it sees the hand on the gun; the starts are where each part roughly sits with the gun held that way
RIGHT = [0.10, 1.30, -0.35, 0, 90]
START = {"slide": [0.10, 1.36, -0.45], "slide-left": [0.02, 1.36, -0.45], "mag": [0.10, 1.20, -0.38], "grip": [0.10, 1.27, -0.70],
         "pump": [0.10, 1.27, -0.70], "bolt": [0.10, 1.38, -0.40], "well": [0.10, 1.25, -0.45],
         "handle": [0.10, 1.20, -0.35], "drum": [0.10, 1.34, -0.42], "insert": [0.10, 1.34, -0.50]}


def pid():
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq re8.exe", "/FO", "CSV"], capture_output=True, text=True).stdout.strip().splitlines()
    return out[-1].split(",")[1].strip('"')


LOG = os.path.join(G, "re2_framework_log.txt")
PAT = re.compile(r"dockreport: gun (\d+), the (.+?): the palm sits ([\d.]+) cm from the part \(right ([-+\d.]+), up ([-+\d.]+), "
                 r"forward ([-+\d.]+) cm, the gun's axes\); the hand turned yaw ([-\d]+) pitch ([-\d]+) roll ([-\d]+)")


def game_time():   # where the log ends now: only lines after it count for the next hold
    return os.path.getsize(LOG)


def last_row(zone_name, since):
    with open(LOG, "rb") as f:
        f.seek(max(0, since - 10))
        text = f.read().decode("utf-8", "replace")
    rows = [m for m in PAT.finditer(text) if m.group(2) == zone_name]
    if not rows:
        return None
    keys = ["gun", "zone", "gap_cm", "right_cm", "up_cm", "fwd_cm", "hand_yaw", "hand_pitch", "hand_roll"]
    return dict(zip(keys, rows[-1].groups()))


def main():
    key, zones = sys.argv[1], sys.argv[2:]
    p = walk.load()
    p["right"] = list(RIGHT)
    p["squeeze"] = 0.0
    p["trigger"] = 0.0
    walk.put(p)
    if key != "-":
        subprocess.run([sys.executable, os.path.join(HERE, "keys.py"), pid(), key], capture_output=True)
        time.sleep(3.5)
    for z in zones:
        p = walk.load()
        p["left"] = START.get(z, [0.10, 1.3, -0.45]) + [0, 90]
        p["squeeze"] = 0.0
        walk.put(p)
        time.sleep(0.6)
        r = subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), z], capture_output=True, text=True)
        walked = r.stdout.strip() or r.stderr.strip()[-200:]
        since = game_time()
        subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), "squeeze", "1"], capture_output=True)
        time.sleep(1.6)
        row = last_row(NAMES[z], since)
        subprocess.run([sys.executable, os.path.join(HERE, "..", "scope_measure.py"), "shot",
                        os.path.join(os.environ["TEMP"], f"dock_{key}_{z}.png")], capture_output=True)
        subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), "squeeze", "0"], capture_output=True)
        time.sleep(0.8)
        if row:
            print(f"{z}: walked ({walked}); gun {row['gun']}: palm {row['gap_cm']} cm off (right {row['right_cm']}, up {row['up_cm']}, "
                  f"fwd {row['fwd_cm']}); hand yaw {row['hand_yaw']} pitch {row['hand_pitch']} roll {row['hand_roll']}", flush=True)
        else:
            print(f"{z}: walked ({walked}); NO DOCK REPORT (LG did not take it?)", flush=True)


if __name__ == "__main__":
    main()
