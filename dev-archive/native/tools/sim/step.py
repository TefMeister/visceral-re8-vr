"""step.py [wait=s] [pic=out.png] [raw:key=v ...] key=value ... -- one robot step and what the mod's log said about it (2026-11-23).
key=value are hv.py's (right= left= in head-view numbers, squeeze= trigger= rsqueeze= rtrigger= rb= ra= lx= ly=); a key
written `raw:left=x,y,z,yaw,pitch` is room numbers as walk.py prints them. wait = seconds before the log is read (0.8).
STEP_GAME_DIR / RV_GAME_DIR picks another game's folder (its re2_framework_log.txt). Prints the new log lines, filtered like guncheck.py."""
import os, sys, time, json, subprocess
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import hv
GAME = os.environ.get("STEP_GAME_DIR") or os.environ.get("RV_GAME_DIR", r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE")
LOG = os.path.join(GAME, "re2_framework_log.txt")
SKIP = ("freehand probe", "gunreport", "smooth]", "forearm:", "accuracy: both", "accuracy: one", "pad:", "holsters]", "dockreport",
        "whitepoint", "armstretch", "mag2] check", "sounds]", "game's reload skipped", "pairs: left hand area", "mesh parts", "ammo:",
        "dockpose", "smooth:", "sound:", "fingers:", "shellclip", "magdisp", "recoil:", "accuracy: the left", "mag2]", "magthrow]", "rides along", "right hand area")
wait, pic, P = 0.8, None, os.path.join(HERE, "pose_now.json")
p = json.load(open(P)); m = os.path.getsize(LOG)
for a in sys.argv[1:]:
    k, v = a.split("=", 1)
    if k == "wait": wait = float(v)
    elif k == "pic": pic = v
    elif k.startswith("raw:"): p[k[4:]] = [float(x) for x in v.split(",")]
    else:
        f = [float(x) for x in v.split(",")]
        if k in ("right", "left"): p[k] = hv.room(*f[0:3]) + [hv.YAW + f[3], f[4]] + f[5:6]
        else: p[k] = f[0]
json.dump(p, open(P, "w")); time.sleep(wait)
with open(LOG, "rb") as f:
    f.seek(m); txt = f.read().decode("utf-8", "replace")
tag = os.environ.get("STEP_TAG", "visceral")
for l in [l[l.find(tag):][:240] for l in txt.splitlines() if tag in l and not any(s in l for s in SKIP)][:int(os.environ.get("STEP_N", "14"))]: print("  ", l)
if pic: print(subprocess.run([sys.executable, os.path.join(HERE, "snap.py"), pic, " ".join(sys.argv[1:])[:60]], capture_output=True, text=True).stdout.strip())
