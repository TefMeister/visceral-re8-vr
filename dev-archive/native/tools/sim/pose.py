"""pose.py [Joint=x,y,z | Joint.z=v ...] -- pose the hand THROUGH the Hand Poser window (its remote input, hand-poser-vr
app/Remote.cs, 2026-11-23): the window must be open and connected; it sends the pose to the game, autosaves it under the gun
and spot the hand is at, and keeps UNDO. Tefa 2026-11-23: "please use all the poser family tools for all this": this script
no longer writes pose files itself (the first version of this morning did).
Short joint names: I1 I2 I3 M1.. R1.. P1.. T1 T2 T3 = L_IndexF1 ... L_Thumb3 (prefix r for the right hand: rI1).
RV_GAME_DIR picks another game's folder (RE2 / RE3 name their fingers l_hand_index_0 ...: give those names in full).
Prints the window's answer: which pose file it went to, how many joints were set, any joint it did not know.
2026-11-23 (Hand Poser's new inputs): `unset=J1,J2,...` takes those rows out of the pose in the window (`unset=left` = every left-hand
row the window holds); `save_as=any` also keeps the hand at the spot as "any gun @ <spot>", every gun's fall-back there."""
import json, os, sys, time
GAME = os.environ.get("RV_GAME_DIR", r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE")
D = os.path.join(GAME, "reframework", "data", "hand_poser")
F = {"I": "IndexF", "M": "MiddleF", "R": "RingF", "P": "PinkyF", "T": "Thumb"}
def full(k):
    ax = ""
    if "." in k: k, ax = k.split("."); ax = "." + ax
    side = "L_"
    if k[0] == "r" and len(k) == 3: side, k = "R_", k[1:]
    return (side + F[k[0]] + k[1] if len(k) == 2 and k[0] in F else k) + ax
sets, boxes, ask, unset, save_as = {}, {"mag": {}, "spare": {}, "dock": {}}, False, [], None   # dock.y=1.5 dock.rz=-20 = the LEFT HAND, DOCKED box (the wrist on the gun); a bare `dock` asks what it shows   # mag.y=3.5 = the MAGAZINE IN HAND box; spare.x=3 spare.rz=20 = the spare's place
for a in sys.argv[1:]:
    if a == "dock": ask = True; continue
    if a.startswith("unset="):
        v = a.split("=", 1)[1]
        if v == "left":   # every left-hand row the window holds (its state.json lists them)
            v = ",".join(n for n in json.load(open(os.path.join(D, "state.json"))).get("angles", {}) if n.lower().startswith("l_"))
        unset += [full(x) for x in v.split(",") if x]; continue
    if a == "save_as=any": save_as = "any gun"; continue
    k, v = a.split("="); v = [float(x) for x in v.split(",")]
    if k.split(".")[0] in boxes: boxes[k.split(".")[0]][k.split(".")[1]] = v[0]
    else: sets[full(k)] = v if len(v) == 3 else v[0]
if not sets and not any(boxes.values()) and not ask and not unset and not save_as: print(__doc__); sys.exit(1)
seq = int(time.time() * 1000) % 2000000000
tmp = os.path.join(D, "remote.json.tmp")
msg = {"seq": seq, "set": sets}
msg.update({k: v for k, v in boxes.items() if v})
if ask and not boxes["dock"]: msg["dock"] = {}
if unset: msg["unset"] = unset
if save_as: msg["save_as"] = save_as
with open(tmp, "w") as f: json.dump(msg, f)
os.replace(tmp, os.path.join(D, "remote.json"))
t0 = time.time()
while time.time() - t0 < 6:
    try:
        a = json.load(open(os.path.join(D, "remote_done.json")))
        if a.get("seq") == seq:
            print("%s: %d joint(s) set in pose '%s' (%d held)%s" % ("ok" if a.get("ok") else "NOT SET", a.get("set", 0), a.get("pose", ""),
                  a.get("held", 0), (" | " + a["note"]) if a.get("note") else ""))
            if ask or boxes["dock"]: print("dock: " + json.dumps(a.get("dock")))
            sys.exit(0 if a.get("ok") else 1)
    except Exception: pass
    time.sleep(0.15)
print("NO ANSWER in 6 s: is the Hand Poser window open and connected to this game (green top line)?"); sys.exit(2)
