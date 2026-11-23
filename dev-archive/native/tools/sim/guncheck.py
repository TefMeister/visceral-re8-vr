"""guncheck.py <ri id, e.g. ri3046> [long] [steps...] -- one gun's whole hand check on the REAL headset lying on the desk
(Two Frame Sequential, so the desktop window repaints), robot hands by VR Bench, keep.py keeping the pose alive (2026-11-23).
The gun is held side-on across the view; the left hand is walked to every grip zone that is on, and each stage is pictured:
free in the zone (ready), LG, LG + LT, the stroke (slide / pump / bolt), and for magazine guns B + pull out + back in.
Out: <outdir>/<gun>_sheet.png (a contact sheet) and <gun>_log.txt (the mod's log lines per stage). outdir = GUNCHECK_OUT or
the temp folder. Steps (default all): zones mag spare."""
import json, math, os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import walk
from PIL import Image, ImageDraw

GAME = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
LOG = os.path.join(GAME, "re2_framework_log.txt")
OUT = os.environ.get("GUNCHECK_OUT") or os.path.join(os.environ.get("TEMP", "."), "guncheck")
os.makedirs(OUT, exist_ok=True)
gun = sys.argv[1]
LONG = "long" in sys.argv[2:]
steps = [a for a in sys.argv[2:] if a != "long"] or ["zones", "mag"]
PID = open(os.path.join(HERE, "pid.txt")).read().strip()
tiles, report = [], []

def rv(code):
    return subprocess.run([sys.executable, os.path.join(HERE, "rv.py"), "--front", code], capture_output=True, text=True).stdout.strip()

# the headset's place and facing in the room (it lies on the desk)
a = rv("local t=vrmod:get_transform(0); local p=t[3]; local f=t[2]; return string.format('%.3f %.3f %.3f %.3f %.3f', p.x,p.y,p.z,-f.x,-f.z)").split()
hx, hy, hz, fx, fz = [float(v) for v in a[-5:]]
n = math.hypot(fx, fz); fx, fz = fx / n, fz / n
RX, RZ = -fz, fx                      # the view's right
HEAD_YAW = math.degrees(math.atan2(-fx, -fz))
def room(right, up, fwd): return [hx + RX * right + fx * fwd, hy + up, hz + RZ * right + fz * fwd]
BACK = (RX, 0.0, RZ)                  # the gun points to the view's left, so "back along the gun" is the view's right

def log_mark(): return os.path.getsize(LOG)
def log_since(mark, n=14):
    with open(LOG, "rb") as f:
        f.seek(mark); txt = f.read().decode("utf-8", "replace")
    skip = ("freehand probe", "gunreport", "smooth]", "forearm:", "accuracy:", "pad:", "holsters]", "dockreport")
    return [l[40:260] for l in txt.splitlines() if "visceral" in l and not any(s in l for s in skip)][:n]

def shot(label):
    f = os.path.join(OUT, "_t.png")
    subprocess.run([sys.executable, os.path.join(HERE, "shot.py"), f, "1.0"], capture_output=True)
    im = Image.open(f).convert("RGB"); w, h = im.size
    box = (0, int(h * .10), w, int(h * .85)) if LONG else (int(w * .30), int(h * .12), int(w * .86), int(h * .78))
    im = im.crop(box).resize((588, int(588 * (box[3] - box[1]) / (box[2] - box[0]))))
    ImageDraw.Draw(im).text((6, 4), label, fill=(255, 255, 0))
    tiles.append(im)

def stage(label, mark):
    time.sleep(0.5); shot(label); lines = log_since(mark)
    report.append("== " + label); report.extend("   " + l for l in lines); return lines

def setp(**kw):
    p = walk.load(); p.update(kw); walk.put(p); return p
def move_left(d, steps=6, pause=0.12):
    p = walk.load(); s = list(p["left"])
    for i in range(1, steps + 1):
        p["left"] = [s[0] + d[0] * i / steps, s[1] + d[1] * i / steps, s[2] + d[2] * i / steps] + s[3:]; walk.put(p); time.sleep(pause)
def press_b():
    setp(rb=1); time.sleep(0.4); setp(rb=0); time.sleep(0.5)
def zones():
    try: d = json.load(open(walk.STATE))
    except Exception: return {}, 0
    return {z["key"]: z for z in d.get("zones", []) if z.get("on")}, d.get("gun", 0)

# the gun across the view, level, the left hand parked low
r = room(0.30, -0.02, 0.72) if LONG else room(0.06, 0.0, 0.42)
PARK = room(-0.25, -0.30, 0.35) + [HEAD_YAW, 0]
setp(right=r + [HEAD_YAW + 90, 90 if LONG else 55], left=PARK, squeeze=0.0, trigger=0.0, rb=0, rsqueeze=None, rtrigger=None)
num = int(gun[2:])
if zones()[1] != num:
    with open(os.path.join(GAME, "reframework", "data", "finger_rec", "command.txt"), "w") as f: f.write("equip " + gun)
    for _ in range(20):
        time.sleep(0.5)
        if zones()[1] == num: break
    time.sleep(2.0)
zs, g = zones()
report.append("gun %s in hand: %s; zones on: %s" % (gun, g == num, ", ".join("%s (%.0f cm)" % (k, z["r_cm"]) for k, z in zs.items())))
print(report[-1])
if g != num: print("NOT IN HAND"); sys.exit(1)
m = log_mark(); stage("%s held, left hand away" % gun, m)
START = room(-0.02, -0.08, 0.40) if not LONG else room(-0.05, -0.10, 0.60)
found = {}

if "zones" in steps:
    for key in zs:
        setp(left=START + [HEAD_YAW, 0], squeeze=0.0, trigger=0.0); time.sleep(0.4)
        o = subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), key], capture_output=True, text=True).stdout.strip()
        report.append("-- zone %s: %s" % (key, o)); print(key, o)
        if not o.startswith("best"): continue
        found[key] = list(walk.load()["left"])
        m = log_mark(); stage("%s: free in zone '%s'" % (gun, key), m)
        m = log_mark(); setp(squeeze=1.0); l1 = stage("%s: '%s' LG" % (gun, key), m)
        m = log_mark(); setp(trigger=1.0); stage("%s: '%s' LG+LT" % (gun, key), m)
        if key in ("slide", "slide-left", "pump", "bolt", "handle", "hammer"):
            m = log_mark(); d = 0.16 if key == "pump" else 0.10
            move_left([BACK[0] * d, 0, BACK[2] * d]); stage("%s: '%s' pulled back %d cm" % (gun, key, d * 100), m)
            m = log_mark(); move_left([-BACK[0] * d, 0, -BACK[2] * d]); setp(trigger=0.0); time.sleep(0.4)
            report.append("== %s back home" % key); report.extend("   " + l for l in log_since(m))
        setp(trigger=0.0); time.sleep(0.2); setp(squeeze=0.0); time.sleep(0.5)

if "mag" in steps and "mag" in zs:
    if "mag" not in found:
        setp(left=START + [HEAD_YAW, 0]); subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), "mag"], capture_output=True)
        found["mag"] = list(walk.load()["left"])
    setp(left=found["mag"], squeeze=0.0, trigger=0.0); time.sleep(0.5)
    m = log_mark(); setp(squeeze=1.0); time.sleep(0.6); press_b(); stage("%s: mag LG then B" % gun, m)
    m = log_mark(); move_left([0, -0.05, 0], 4); stage("%s: mag pulled 5 cm" % gun, m)
    m = log_mark(); move_left([0, -0.09, 0], 5); stage("%s: mag out, in the hand (14 cm)" % gun, m)
    m = log_mark(); move_left([0, 0.09, 0], 5); stage("%s: mag brought back to 5 cm" % gun, m)
    m = log_mark(); setp(trigger=1.0); move_left([0, 0.06, 0], 5); stage("%s: mag pushed in with LT" % gun, m)
    m = log_mark(); setp(trigger=0.0); time.sleep(0.3); setp(squeeze=0.0); stage("%s: let go" % gun, m)

setp(left=PARK, squeeze=0.0, trigger=0.0)
cols = 2; rows = (len(tiles) + cols - 1) // cols; th = tiles[0].size[1]
sheet = Image.new("RGB", (588 * cols, th * rows))
for i, t in enumerate(tiles): sheet.paste(t, (588 * (i % cols), th * (i // cols)))
sp = os.path.join(OUT, gun + "_sheet.png"); sheet.save(sp)
open(os.path.join(OUT, gun + "_log.txt"), "w", encoding="utf-8").write("\n".join(report))
print("sheet:", sp, "tiles:", len(tiles))
