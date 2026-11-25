"""gm79_spent.py -- Village's GM 79, b170, by robot on the desk headset (2026-11-25, Tefa's spent-shell design):
front grip + LG + LT must NOT move the barrel; a live grenade in, fired; then the spent shell pulled out by hand with a live one in
the hand (it goes in after, by itself), and once more with an empty hand (the spent shell carried away). Needs keep.py running,
HV_HEAD set, the GM 79 equipped and held across the view (right=0.05,0.03,0.32,90,55). Prints the mod's lines per step;
`pics` saves a picture per step into GUNCHECK_OUT."""
import json, os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import hv, walk
PICS = "pics" in sys.argv
OUT = os.environ.get("GUNCHECK_OUT") or os.path.join(os.environ.get("TEMP", "."), "gm79")
os.makedirs(OUT, exist_ok=True)
LOG = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE\re2_framework_log.txt"
KEEP = ("breech:", "pairs:", "reload: ", "re8-grip] grip", "shell2]")
POUCH = hv.room(-0.20, -0.62, 0.02) + [hv.YAW, 0]
RIGHT = hv.room(0.05, 0.03, 0.32) + [hv.YAW + 90, 55]
PARK = hv.room(-0.25, -0.30, 0.30) + [hv.YAW, 0]
n = 0

def mark(): return os.path.getsize(LOG)
def lines(m):
    with open(LOG, "rb") as f:
        f.seek(m); t = f.read().decode("utf-8", "replace")
    return [l[l.find("] [", 30) + 3:][:200] for l in t.splitlines() if any(k in l for k in KEEP) and "JSON" not in l]
def p(): return json.load(open(os.path.join(HERE, "pose_now.json")))
def setp(**kw):
    q = p()
    for k, v in kw.items(): q[k] = v
    walk.put(q); json.dump(q, open(os.path.join(HERE, "pose_now.json"), "w"))
def stage(name, m, wait=0.8):
    global n
    time.sleep(wait); n += 1
    print("== %d %s" % (n, name))
    for l in lines(m): print("   " + l)
    if PICS: subprocess.run([sys.executable, os.path.join(HERE, "shot.py"), os.path.join(OUT, "%02d.png" % n), "0.8"], capture_output=True)
def press(k, s=0.3): setp(**{k: 1.0}); time.sleep(s); setp(**{k: 0.0})
def pitch(vals):
    for v in vals: setp(right=RIGHT[:4] + [v]); time.sleep(0.12)
def flick_open(): pitch([63, 71, 79, 87, 95]); time.sleep(0.6); pitch([55])
def flick_shut(): pitch([47, 39, 31, 23, 15]); time.sleep(0.6); pitch([55])
def walk_to(key):
    r = subprocess.run([sys.executable, os.path.join(HERE, "walk.py"), key], capture_output=True, text=True, timeout=90)
    return p()["left"]
def nudge(dr, du):   # the left hand moved right / up in head-view metres
    l = p()["left"]; setp(left=[l[0] + hv.RX * dr, l[1] + du, l[2] + hv.RZ * dr] + l[3:])

setp(right=RIGHT, left=PARK, squeeze=0.0, trigger=0.0, rb=0.0, rtrigger=0.0); time.sleep(1.0)
if "look" in sys.argv:   # one round in, fired, the spent shell pulled with an empty hand and held up in front of the headset
    m = mark(); press("rb", 0.4); time.sleep(0.8); flick_open(); stage("unlatch, open", m, 1.0)
    m = mark(); setp(left=POUCH); time.sleep(0.9); setp(squeeze=1.0); stage("LG at the pouch", m)
    walk_to("insert"); m = mark(); stage("the chamber end", m, 1.5)
    setp(squeeze=0.0, left=PARK); time.sleep(0.6); flick_shut(); time.sleep(1.0)
    m = mark(); press("rtrigger", 0.3); stage("fire", m, 1.5)
    m = mark(); press("rb", 0.4); time.sleep(0.8); flick_open(); stage("unlatch, open", m, 1.0)
    walk_to("insert"); m = mark(); setp(squeeze=1.0); time.sleep(0.6); press("trigger", 0.3)
    for i in range(8): nudge(0.02, 0.02); time.sleep(0.12)
    stage("LT, pulled out", m, 0.6)
    m = mark(); setp(left=hv.room(-0.02, -0.02, 0.28) + [hv.YAW + 30, 20]); stage("the hand up in front of the headset, LG held", m, 1.2)
    sys.exit()
# 1 the front grip: LG + LT there must not move the barrel any more (b170)
m = mark(); press("rb", 0.4); stage("right B: unlatch", m, 1.0)
walk_to("grip"); m = mark(); setp(squeeze=1.0); time.sleep(0.6); setp(trigger=1.0)
for d in (0.03, 0.06, 0.09): nudge(0, -d / 3); time.sleep(0.15)
stage("front grip, LG + LT, hand 9 cm down: NOTHING should move", m)
setp(trigger=0.0, squeeze=0.0, left=PARK); time.sleep(0.6)
# 2 a live grenade in: open, pouch, the chamber end
m = mark(); flick_open(); stage("flick down: open", m, 1.0)
m = mark(); setp(left=POUCH); time.sleep(0.9); setp(squeeze=1.0); stage("LG at the pouch", m)
walk_to("insert"); m = mark(); stage("brought to the chamber end", m, 1.5)
m = mark(); setp(squeeze=0.0, left=PARK); stage("let go", m)
m = mark(); flick_shut(); stage("flick up: shut", m, 1.0)
m = mark(); press("rtrigger", 0.3); stage("fire", m, 1.5)
# 3 the spent shell out with a live one in the hand
m = mark(); press("rb", 0.4); time.sleep(0.8); flick_open(); stage("unlatch, open", m, 1.0)
m = mark(); setp(left=POUCH); time.sleep(0.9); setp(squeeze=1.0); stage("LG at the pouch: a live one", m)
walk_to("insert"); m = mark(); stage("the live one at the chamber end: docks", m, 1.2)
m = mark(); press("trigger", 0.3); stage("LT: thumb and finger on the spent shell", m, 0.6)
for i in range(8):
    nudge(0.02, 0.02); time.sleep(0.12)
m2 = mark(); stage("pulled out about 16 cm (right and up in the view)", m2, 0.2)
time.sleep(0.8); m = mark(); stage("after the push-in", m, 0.2)
m = mark(); setp(squeeze=0.0, left=PARK); stage("LG let go: the spent shell thrown", m)
# 4 the spent shell out with an empty hand: fire first
m = mark(); flick_shut(); stage("flick up: shut", m, 1.0)
m = mark(); press("rtrigger", 0.3); stage("fire", m, 1.5)
m = mark(); press("rb", 0.4); time.sleep(0.8); flick_open(); stage("unlatch, open", m, 1.0)
walk_to("insert"); m = mark(); setp(squeeze=1.0); stage("LG at the chamber end, empty hand", m)
m = mark(); press("trigger", 0.3); stage("LT on the spent shell", m, 0.6)
for i in range(8):
    nudge(0.02, 0.02); time.sleep(0.12)
m = mark(); stage("pulled out: the hand carries it away", m, 0.5)
m = mark(); setp(left=PARK); stage("hand away, LG still held", m)
m = mark(); setp(squeeze=0.0); stage("LG let go", m)
