"""partscan.py <first> <last> [box] -- which mesh part of the held gun is its shell / grenade (2026-11-25, the GM 79 for b170): the
second-shell copy (visceral_re8_shell2.lua) floats 0.35 m in front of the camera with one part on at a time; each part's picture
is compared with one without the copy, inside the middle of the view (box = the share of the width / height, default 0.3).
Prints the parts that changed the picture, the biggest first. The game window must be in front; keep the head still."""
import json, os, subprocess, sys, time
from PIL import Image, ImageChops, ImageStat
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
TEST = os.path.join(GAME, "reframework", "data", "visceral_re8", "shell2_test.json")
OUT = os.path.join(os.environ.get("TEMP", "."), "partscan"); os.makedirs(OUT, exist_ok=True)
a, b = int(sys.argv[1]), int(sys.argv[2]); box = float(sys.argv[3]) if len(sys.argv) > 3 else 0.3
FRONT = "inplace" not in sys.argv   # inplace: the copy stays where the plugin draws it (shell2.lua b170 override)
pid = open(os.path.join(HERE, "pid.txt")).read().strip()
def shot(name):
    subprocess.run([sys.executable, os.path.join(HERE, "keys.py"), pid], capture_output=True)
    path = os.path.join(OUT, name + ".png")
    subprocess.run([sys.executable, os.path.join(HERE, "shot.py"), path, str(box)], capture_output=True)
    return Image.open(path).convert("L")
if os.path.exists(TEST): os.remove(TEST)
time.sleep(1.5); base = shot("base")
res = []
for p in range(a, b + 1):
    json.dump({"front": FRONT, "part": p}, open(TEST, "w")); time.sleep(1.6)
    im = shot("p%02d" % p)
    d = ImageStat.Stat(ImageChops.difference(base, im)).mean[0]
    res.append((d, p)); print("part %d: %.2f" % (p, d), flush=True)
os.remove(TEST)
print("CHANGED MOST:", ", ".join("part %d (%.1f)" % (p, d) for d, p in sorted(res, reverse=True)[:6]))
