"""axes_hand.py <axes_out.json> -- the finger / thumb / wrist table from zz_test_axes.lua's measurement, in the hand's own frame,
so it holds whatever way the hand is held (2026-11-08). Per joint and axis: kind (bend / side / turn) from the bone's frame, and
the word for + in Tefa's rule, read as the player sees a hand held out palm-down:
  bend: IN (toward the palm; on the wrist: DOWN) / OUT (UP); side: LEFT / RIGHT (palm-down: the left hand's thumb is on the right,
  the right hand's on the left); turn: TURN LEFT / TURN RIGHT (seen from behind the hand, along the finger: anticlockwise = left)."""
import json, math, sys
sys.path.insert(0, __import__("os").path.dirname(__file__))
from axes_read import sub, add, mul, dot, cross, norm, ortho, CHILD, PARENT

d = json.load(open(sys.argv[1]))
J, P = d["joints"], d["points"]
table = {}
for name, rec in sorted(J.items()):
    side, part = name[:2], name[2:]
    jp = rec["pos"]
    if part in CHILD: tip = J[side + CHILD[part]]["pos"] if side + CHILD[part] in J else P[side + CHILD[part]]
    else: tip = add(jp, sub(jp, J[side + PARENT[part]]["pos"]))
    bone = norm(sub(tip, jp))
    hand, mf1, if1, pf1, mf3 = P[side + "Hand"], P[side + "MiddleF1"], P[side + "IndexF1"], P[side + "PinkyF1"], P[side + "MiddleF3"]
    hfwd = norm(sub(mf1, hand)); thumbward = ortho(sub(if1, pf1), hfwd)
    palm = ortho(ortho(sub(mf3, mf1), hfwd), thumbward)
    hinge = norm(cross(hfwd, palm))                      # +turn about it curls toward the palm
    thumb_is_right = side == "L_"                        # palm-down view
    n = ortho(palm, bone); lat = norm(cross(n, bone))
    row = {}
    for k, ax in enumerate("XYZ"):
        w = rec["axes"][k]
        cb, cs, ct = abs(dot(w, lat)), abs(dot(w, n)), abs(dot(w, bone))
        if part.startswith("Thumb"):                     # the thumb's own hinge: its bone frame
            bend_in = dot(cross(w, bone), n) > 0
        else:
            bend_in = dot(w, hinge) > 0
        to_thumb = dot(cross(w, bone), thumbward) > 0
        if ct >= max(cb, cs): kind, word = "turn", ("TURN RIGHT" if dot(w, bone) > 0 else "TURN LEFT")
        elif cb >= cs: kind, word = "bend", (("DOWN" if bend_in else "UP") if part == "Hand" else ("IN" if bend_in else "OUT"))
        else: kind, word = "side", ("RIGHT" if to_thumb == thumb_is_right else "LEFT")
        row[ax] = [kind, word]
    table[name] = row
    print(f"{name:11s} " + "  ".join(f"+{a}: {row[a][1]:10s}" for a in "XYZ"))
out = sys.argv[1].replace("axes_out.json", "hand_axes.json")
json.dump(table, open(out, "w"), indent=1); print("wrote", out)
