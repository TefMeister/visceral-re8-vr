"""pose.py "<gun> @ <spot>" [from="<other pose name>"] [Joint=x,y,z | Joint.z=v ...] -- write / change one Hand Poser pose file
(degrees, the app's own format) in BOTH places: the app's folder (%APPDATA%/HandPoserVR/re8/guns, the master) and the game's copy
(reframework/data/hand_poser/guns). A new file starts from from= (default: the gun's own pose, left hand joints only).
Short joint names: I1 I2 I3 M1.. R1.. P1.. T1 T2 T3 = L_IndexF1 ... L_Thumb3 (prefix r: for the right hand, e.g. rI1).
The game re-reads a pose when the gun or the hand's spot changes (2026-11-23)."""
import json, os, sys
A = os.path.join(os.environ["APPDATA"], "HandPoserVR", "re8", "guns")
G = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE\reframework\data\hand_poser\guns"
F = {"I": "IndexF", "M": "MiddleF", "R": "RingF", "P": "PinkyF", "T": "Thumb"}
def full(k):
    side = "L_"
    if k[0] == "r": side, k = "R_", k[1:]
    return side + F[k[0]] + k[1] if len(k) == 2 and k[0] in F else k
name = sys.argv[1]; path = os.path.join(G, name + ".json")
args = sys.argv[2:]; src = None
for a in list(args):
    if a.startswith("from="): src = a[5:]; args.remove(a)
if os.path.exists(path) and src is None: d = json.load(open(path))
else:
    base = json.load(open(os.path.join(G, (src or name.split(" @ ")[0]) + ".json")))
    d = {"game": "re8", "character": "pl1000", "joints": {k: v for k, v in base["joints"].items() if k.startswith("L_")}}
for a in args:
    k, v = a.split("=")
    if "." in k:
        k, ax = k.split("."); d["joints"].setdefault(full(k), [0, 0, 0])["xyz".index(ax)] = float(v)
    else: d["joints"][full(k)] = [float(x) for x in v.split(",")]
for folder in (A, G):
    with open(os.path.join(folder, name + ".json"), "w") as f: json.dump(d, f)
print("wrote", name, "(%d joints)" % len(d["joints"]))
