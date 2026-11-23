"""zone.py <zone> [group=all] [forward=cm] [up=cm] [right=cm] [size=cm] -- move or size one grip zone THROUGH the Grip Zones
window (its remote input, grip-zones-vr app/Remote.cs, 2026-11-23): the window must be open. The gun in hand unless group=all.
Prints the window's answer."""
import json, os, sys, time
D = os.path.join(os.environ.get("RV_GAME_DIR", r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"), "reframework", "data", "visceral_re8")
if len(sys.argv) < 3: print(__doc__); sys.exit(1)
seq = int(time.time() * 1000) % 2000000000
msg = {"seq": seq, "zone": sys.argv[1]}
for a in sys.argv[2:]:
    k, v = a.split("="); msg[k] = v if k == "group" else float(v)
tmp = os.path.join(D, "zones_remote.json.tmp")
with open(tmp, "w") as f: json.dump(msg, f)
os.replace(tmp, os.path.join(D, "zones_remote.json"))
t0 = time.time()
while time.time() - t0 < 6:
    try:
        a = json.load(open(os.path.join(D, "zones_remote_done.json")))
        if a.get("seq") == seq:
            print("%s: zone %s of %s%s" % ("ok" if a.get("ok") else "NOT SET", sys.argv[1], a.get("group") or "?", (" | " + a["note"]) if a.get("note") else "")); sys.exit(0 if a.get("ok") else 1)
    except Exception: pass
    time.sleep(0.15)
print("NO ANSWER in 6 s: is the Grip Zones window open?"); sys.exit(2)
