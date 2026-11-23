"""guncheck.py <ri id, e.g. ri3046> [long] [pics] [steps...] -- one gun's whole hand check on the REAL headset lying on the desk
(Two Frame Sequential, so the desktop window repaints), robot hands by VR Bench, keep.py keeping the pose alive (2026-11-23).
The gun is held side-on across the view. Steps (default: zones fire mag spare rounds):
  zones  the left hand walked to every grip zone that is on: LG, LG + LT, a pull back along the gun and home, let go
  fire   RT pulled until the gun stops firing (so a rack is due), then the slide / pump / bolt zones once more
  mag    magazine guns: LG on the magazine, B, pulled out, brought back, LT pushes it in
  spare  magazine guns: a spare from the pouch, docked under the seated one, B, out, LT seats the spare, LG let go
  rounds round-fed guns: LG at the pouch, the hand to the insert / drum zone, LT
Out: <outdir>/<gun>_log.txt (the mod's log lines per stage; the thing to read) and, with `pics`, <gun>_sheet.png.
outdir = GUNCHECK_OUT or the temp folder."""
import json, os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import walk, hv
from PIL import Image, ImageDraw

GAME = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
LOG = os.path.join(GAME, "re2_framework_log.txt")
OUT = os.environ.get("GUNCHECK_OUT") or os.path.join(os.environ.get("TEMP", "."), "guncheck")
os.makedirs(OUT, exist_ok=True)
gun = sys.argv[1]
flags = sys.argv[2:]
LONG, PICS = "long" in flags, "pics" in flags
steps = [a for a in flags if a not in ("long", "pics")] or ["zones", "fire", "mag", "spare", "rounds"]
PID = open(os.path.join(HERE, "pid.txt")).read().strip()
tiles, report = [], []
SKIP = ("freehand probe", "gunreport", "smooth]", "forearm:", "accuracy: both", "accuracy: one", "pad:", "holsters]", "dockreport",
        "whitepoint", "armstretch", "mag2] check", "sounds]", "game's reload skipped", "pairs:", "mesh parts", "ammo:",
        "dockpose", "smooth:", "sound:", "fingers:", "shellclip", "magdisp", "recoil:", "accuracy: shot", "accuracy: the left", "mag2]", "magthrow]", "rides along")
BACK = (hv.RX, 0.0, hv.RZ)            # the gun points to the view's left, so "back along the gun" is the view's right

def front(): subprocess.run([sys.executable, os.path.join(HERE, "keys.py"), PID], capture_output=True)
def log_mark(): return os.path.getsize(LOG)
def log_since(mark, n=16):
    with open(LOG, "rb") as f:
        f.seek(mark); txt = f.read().decode("utf-8", "replace")
    return [l[l.find("visceral"):][:230] for l in txt.splitlines() if "visceral" in l and not any(s in l for s in SKIP)][:n]
def shot(label):
    if not PICS: return
    f = os.path.join(OUT, "_t.png")
    subprocess.run([sys.executable, os.path.join(HERE, "shot.py"), f, "1.0"], capture_output=True)
    im = Image.open(f).convert("RGB"); w, h = im.size
    box = (0, int(h * .05), w, int(h * .90)) if LONG else (int(w * .17), int(h * .06), int(w * .94), int(h * .97))
    im = im.crop(box).resize((588, int(588 * (box[3] - box[1]) / (box[2] - box[0]))))
    ImageDraw.Draw(im).text((6, 4), label, fill=(255, 255, 0)); tiles.append(im)
def stage(label, mark, wait=0.7):
    time.sleep(wait); shot(label); lines = log_since(mark)
    report.append("== " + label); report.extend("   " + l for l in lines); return "\n".join(lines)
def setp(**kw):
    p = walk.load(); p.update(kw); walk.put(p); return p
def move_left(d, steps=6, pause=0.12):
    p = walk.load(); s = list(p["left"])
    for i in range(1, steps + 1):
        p["left"] = [s[0] + d[0] * i / steps, s[1] + d[1] * i / steps, s[2] + d[2] * i / steps] + s[3:]; walk.put(p); time.sleep(pause)
def press(key, sec=0.4):
    setp(**{key: 1}); time.sleep(sec); setp(**{key: 0}); time.sleep(0.5)
def zones():
    try: d = json.load(open(walk.STATE))
    except Exception: return {}, 0
    return {z["key"]: z for z in d.get("zones", []) if z.get("on")}, d.get("gun", 0)
def walk_to(key):
    setp(left=START + [hv.YAW, 0]); time.sleep(0.4)
    o = subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), key], capture_output=True, text=True).stdout.strip()
    report.append("-- zone %s: %s" % (key, o))
    return list(walk.load()["left"]) if o.startswith("best") else None
STROKE = ("slide", "slide-left", "pump", "bolt", "handle", "hammer", "drum")
def work_zone(key, tag=""):
    at = walk_to(key)
    if at is None: return
    m = log_mark(); setp(squeeze=1.0); stage("%s'%s' LG" % (tag, key), m)
    if LONG and key in ("mag", "well"):   # on a long gun LT pulls the magazine out: that is the `mag` step's job
        m = log_mark(); setp(squeeze=0.0); stage("%s'%s' let go" % (tag, key), m, 0.5); return
    m = log_mark(); setp(trigger=1.0); stage("%s'%s' LG+LT" % (tag, key), m)
    if key in STROKE:
        d = 0.18 if key == "pump" else 0.11
        m = log_mark(); move_left([BACK[0] * d, 0, BACK[2] * d]); stage("%s'%s' pulled back %d cm" % (tag, key, d * 100), m)
        m = log_mark(); move_left([-BACK[0] * d, 0, -BACK[2] * d]); stage("%s'%s' pushed home" % (tag, key), m, 0.5)
    m = log_mark(); setp(trigger=0.0); time.sleep(0.3); setp(squeeze=0.0); stage("%s'%s' let go" % (tag, key), m, 0.5)

front()
r = hv.room(0.30, 0.0, 0.70) if LONG else hv.room(0.05, 0.03, 0.32)
PARK = hv.room(-0.25, -0.30, 0.30) + [hv.YAW, 0]
POUCH = hv.room(-0.20, -0.62, 0.02) + [hv.YAW, 0]
START = hv.room(-0.02, -0.10, 0.30) if not LONG else hv.room(-0.05, -0.10, 0.60)
setp(right=r + [hv.YAW + 90, 90 if LONG else 55], left=PARK, squeeze=0.0, trigger=0.0, rb=0, rsqueeze=None, rtrigger=0.0)
num = int(gun[2:])
if zones()[1] != num:
    with open(os.path.join(GAME, "reframework", "data", "finger_rec", "command.txt"), "w") as f: f.write("equip " + gun)
    for _ in range(24):
        time.sleep(0.5)
        if zones()[1] == num: break
    time.sleep(2.5)
zs, g = zones()
report.append("gun %s in hand: %s; zones on: %s" % (gun, g == num, ", ".join("%s (%.0f cm)" % (k, z["r_cm"]) for k, z in zs.items())))
print(report[-1])
if g != num: print("NOT IN HAND"); sys.exit(1)

if "zones" in steps:
    for key in zs: work_zone(key)
if "fire" in steps:
    m = log_mark(); n = 0
    for i in range(40):
        m2 = log_mark(); press("rtrigger", 0.15)
        t = "\n".join(log_since(m2, 40))
        if "accuracy: shot" in open(LOG, "rb").read()[m2:].decode("utf-8", "replace"): n += 1
        elif "refused" in t or i > n + 2: break
    stage("fired until it stopped: %d shots" % n, m)
    for key in zones()[0]:
        if key in STROKE: work_zone(key, "after firing: ")
if "mag" in steps and LONG and "mag" in zones()[0]:
    at = walk_to("mag")
    m = log_mark(); setp(squeeze=1.0); time.sleep(0.6); setp(trigger=1.0); time.sleep(0.5); setp(trigger=0.0); stage("long mag: LG, LT pulls it out", m)
    m = log_mark(); move_left([0, -0.15, 0], 6); time.sleep(1.2); setp(squeeze=0.0); stage("long mag: taken 15 cm down, held still, LG let go", m)
    m = log_mark(); setp(left=POUCH); time.sleep(0.9); setp(squeeze=1.0); stage("long mag: LG at the pouch", m)
    m = log_mark(); setp(left=[at[0], at[1] - 0.12, at[2]] + at[3:]); time.sleep(0.8); move_left([0, 0.12, 0], 6); stage("long mag: brought up to the well", m, 1.3)
    # (2026-11-23: no LT here: on a long gun LT at the seated magazine pulls it straight out again, and the rack below never ran)
    m = log_mark(); setp(squeeze=0.0); stage("long mag: let go", m)
    for key in zones()[0]:
        if key in STROKE: work_zone(key, "after the reload: ")
    steps = [s for s in steps if s not in ("mag", "spare")]
if "mag" in steps and "mag" in zones()[0]:
    walk_to("mag")
    m = log_mark(); setp(squeeze=1.0); time.sleep(0.6); press("rb"); stage("mag: LG then B", m)
    m = log_mark(); move_left([0, -0.16, 0], 8); stage("mag: pulled 16 cm down", m)
    m = log_mark(); move_left([0, 0.10, 0], 5); stage("mag: brought back to 6 cm", m)
    m = log_mark(); setp(trigger=1.0); move_left([0, 0.06, 0], 5); stage("mag: pushed in with LT", m, 1.2)
    m = log_mark(); setp(trigger=0.0); time.sleep(0.3); setp(squeeze=0.0); stage("mag: let go", m)
if "spare" in steps and "mag" in zones()[0]:
    at = walk_to("mag")
    m = log_mark(); setp(left=POUCH); time.sleep(0.9); setp(squeeze=1.0); stage("spare: LG at the pouch", m)
    m = log_mark(); setp(left=at); stage("spare: brought to the seated magazine", m, 1.3)
    m = log_mark(); press("rb"); stage("spare: B", m)
    m = log_mark(); move_left([0, -0.16, 0], 8); stage("spare: old magazine pulled out", m)
    m = log_mark(); setp(trigger=1.0); time.sleep(0.3); move_left([0, 0.16, 0], 8); stage("spare: LT, back up to the gun", m, 1.2)
    m = log_mark(); setp(trigger=0.0); time.sleep(0.3); move_left([0, -0.12, 0], 6); time.sleep(1.5); setp(squeeze=0.0); stage("spare: hand away, held still 1.5 s, LG let go", m)
if "rounds" in steps and any(k in zones()[0] for k in ("insert", "drum")):
    key = "insert" if "insert" in zones()[0] else "drum"
    at = walk_to(key)
    m = log_mark(); setp(left=POUCH); time.sleep(0.9); setp(squeeze=1.0); stage("rounds: LG at the pouch", m)
    if at:
        m = log_mark(); setp(left=at); stage("rounds: brought to '%s'" % key, m, 1.3)
        for i in (1, 2):
            m = log_mark(); press("trigger", 0.3); stage("rounds: LT press %d" % i, m)
    m = log_mark(); setp(squeeze=0.0); stage("rounds: let go", m)

setp(left=PARK, squeeze=0.0, trigger=0.0)
open(os.path.join(OUT, gun + "_log.txt"), "w", encoding="utf-8").write("\n".join(report))
if tiles:
    cols = 2; rows = (len(tiles) + cols - 1) // cols; th = tiles[0].size[1]
    sheet = Image.new("RGB", (588 * cols, th * rows))
    for i, t in enumerate(tiles): sheet.paste(t, (588 * (i % cols), th * (i // cols)))
    sheet.save(os.path.join(OUT, gun + "_sheet.png"))
print("\n".join(report))
