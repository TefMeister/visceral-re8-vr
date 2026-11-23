"""rgrip.py [name=value ...] [show] -- pose the RIGHT hand through the Hand Poser window by the curl of each finger (2026-11-23):
index= middle= ring= pinky= take three numbers "k1,k2,k3" (degrees of bend at knuckle, middle joint, tip joint; on the right hand
a bend is a POSITIVE z) and keep each joint's other two angles as the game has them now; thumb=x1,y1,z1,x2,y2,z2,x3,y3,z3 sets the
thumb whole; thumb=lemi copies the LEMI's kept thumb. `show` prints the right hand's angles now. It lands in the pose the window
is on (the gun's own pose when no right-hand spot is named there). RV_GAME_DIR for another game."""
import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.environ.get("RV_GAME_DIR", r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE")
D = os.path.join(GAME, "reframework", "data", "hand_poser")
ang = json.load(open(os.path.join(D, "state.json")))["angles"]
F = {"index": "R_IndexF", "middle": "R_MiddleF", "ring": "R_RingF", "pinky": "R_PinkyF"}
if "show" in sys.argv:
    for k in sorted(a for a in ang if a.startswith("R_")): print(k, " ".join("%.0f" % v for v in ang[k]))
    sys.exit()
args = []
for a in sys.argv[1:]:
    k, v = a.split("=")
    if k in F:
        for i, c in enumerate(float(x) for x in v.split(",")):
            cur = ang.get(F[k] + str(i + 1), [0, 0, 0]); args.append("%s%d=%.1f,%.1f,%.1f" % (F[k], i + 1, cur[0], cur[1], c))
    elif k == "thumb":
        if v == "lemi":
            d = json.load(open(os.path.join(D, "guns", "ri3046_Inventory.json")))["joints"]
            for i in (1, 2, 3): args.append("R_Thumb%d=%.1f,%.1f,%.1f" % (i, *d["R_Thumb%d" % i]))
        else:
            n = [float(x) for x in v.split(",")]
            for i in range(3): args.append("R_Thumb%d=%.1f,%.1f,%.1f" % (i + 1, *n[i * 3:i * 3 + 3]))
print(subprocess.run([sys.executable, os.path.join(HERE, "pose.py")] + args, capture_output=True, text=True).stdout.strip())
