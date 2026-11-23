"""posefile.py <gun> "<spot>" [fingers] -- print a kept Hand Poser pose's LEFT joints as pose.py arguments (to send it again through
the window at another stage or gun). fingers: letters of T I M R P to keep (default all). 2026-11-23."""
import json, os, sys
GAME = os.environ.get("RV_GAME_DIR", r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE")
gun, spot = sys.argv[1], sys.argv[2]; keep = sys.argv[3] if len(sys.argv) > 3 else "TIMRP"
name = gun + "_Inventory" + ((" @ " + spot) if spot else "")
d = json.load(open(os.path.join(GAME, "reframework", "data", "hand_poser", "guns", name + ".json")))["joints"]
S = {"Thumb": "T", "IndexF": "I", "MiddleF": "M", "RingF": "R", "PinkyF": "P"}
out = []
for k, v in sorted(d.items()):
    if not k.startswith("L_") or not isinstance(v, list): continue
    for long, s in S.items():
        if k[2:-1] == long and s in keep: out.append("%s%s=%.1f,%.1f,%.1f" % (s, k[-1], v[0], v[1], v[2]))
print(" ".join(out))
