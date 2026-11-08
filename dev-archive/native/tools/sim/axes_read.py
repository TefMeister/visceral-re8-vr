"""axes_read.py <axes_out.json> -- reads zz_test_axes.lua's measurement: for every hand joint and each of its X / Y / Z Euler
axes, what +10 degrees does, in the words of Tefa's rule (2026-11-08: "left side must always be down, inwards, rotate left,
bend left ... right must always be up, outwards, rotate right"):
  fingers and thumb: IN (curls toward the palm) / OUT, LEFT / RIGHT (as the player sees it), TURN LEFT / TURN RIGHT (about the bone,
  counter-clockwise / clockwise as seen from the player's eye)
  the wrist (Hand): DOWN / UP (the fingers), LEFT / RIGHT, TURN LEFT / TURN RIGHT (about the forearm)
Prints one line per joint axis and writes axes_table.json: {joint: {"X": [kind, plus_word], ...}} for the apps.
The player's left / right is taken from the two hands (the right hand is to the right) and up as world +Y; the view's
handedness is measured, not assumed."""
import json, math, sys


def sub(a, b): return [a[i] - b[i] for i in range(3)]
def add(a, b): return [a[i] + b[i] for i in range(3)]
def mul(a, s): return [x * s for x in a]
def dot(a, b): return sum(a[i] * b[i] for i in range(3))
def cross(a, b): return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
def norm(a):
    n = math.sqrt(dot(a, a))
    return mul(a, 1 / n) if n > 1e-9 else [0, 0, 0]
def ortho(a, b): return norm(sub(a, mul(b, dot(a, b))))   # a with b taken out


CHILD = {"Thumb1": "Thumb2", "Thumb2": "Thumb3", "IndexF1": "IndexF2", "IndexF2": "IndexF3", "MiddleF1": "MiddleF2",
         "MiddleF2": "MiddleF3", "RingF1": "RingF2", "RingF2": "RingF3", "PinkyF1": "PinkyF2", "PinkyF2": "PinkyF3", "Hand": "MiddleF1"}
PARENT = {v: k for k, v in CHILD.items() if k != "Hand"}


def main(path):
    d = json.load(open(path))
    J, P = d["joints"], d["points"]
    up = [0, 1, 0]
    right = ortho(sub(P["R_Hand"], P["L_Hand"]), up)        # the player's right
    cam = d["camera"]["pos"]
    mid = mul(add(P["R_Hand"], P["L_Hand"]), 0.5)
    fwd = ortho(sub(mid, cam), up)                            # away from the player, level
    # the view's handedness: right x up points TOWARD the viewer in a right-handed world
    rh = dot(cross(right, up), fwd) < 0
    print("view: right-handed" if rh else "view: LEFT-handed", "| right", [round(x, 2) for x in right], "fwd", [round(x, 2) for x in fwd])
    table = {}
    for name, rec in sorted(J.items()):
        side, part = name[:2], name[2:]
        jp = rec["pos"]
        if part in CHILD:
            tip = J[side + CHILD[part]]["pos"] if side + CHILD[part] in J else P.get(side + CHILD[part])
        else:   # a last joint: one bone length on from its parent
            par = J[side + PARENT[part]]["pos"]
            tip = add(jp, sub(jp, par))
        bone = norm(sub(tip, jp))
        hand, mf1, if1, pf1, mf3 = P[side + "Hand"], P[side + "MiddleF1"], P[side + "IndexF1"], P[side + "PinkyF1"], P[side + "MiddleF3"]
        hfwd = norm(sub(mf1, hand))
        thumbward = ortho(sub(if1, pf1), hfwd)
        palm = ortho(ortho(sub(mf3, mf1), hfwd), thumbward)   # the side the fingers curl to
        if dot(palm, palm) < 0.5:
            palm = norm(cross(hfwd, thumbward))
        row = {}
        n = ortho(palm, bone)                 # the finger's own frame: along the bone, toward the palm, and across
        lat = norm(cross(n, bone))
        for k, ax in enumerate("XYZ"):
            w = rec["axes"][k]
            c_bend, c_side, c_turn = abs(dot(w, lat)), abs(dot(w, n)), abs(dot(w, bone))
            tipmove = cross(w, bone)
            if part == "Hand":
                upmove = dot(tipmove, up)
                c_bend_w = c_bend
            if c_turn >= max(c_bend, c_side):
                tv = -dot(bone, fwd) * dot(w, bone)       # the twist's axis toward the viewer (+) or away
                ccw = (tv > 0) == rh
                kind, word = "turn", ("TURN LEFT" if ccw else "TURN RIGHT")
            elif c_bend >= c_side:
                if part == "Hand":
                    kind, word = "updown", ("UP" if dot(tipmove, up) > 0 else "DOWN")
                else:
                    kind, word = "bend", ("IN" if dot(tipmove, n) > 0 else "OUT")
            else:
                kind, word = "side", ("RIGHT" if dot(tipmove, right) > 0 else "LEFT")
            row[ax] = [kind, word]
            total = c_bend + c_side + c_turn
            print(f"{name:12s} +{ax}: {word:10s} ({kind}; bend {c_bend/total:.2f} side {c_side/total:.2f} turn {c_turn/total:.2f})")
        table[name] = row
    out = path.replace("axes_out.json", "axes_table.json")
    json.dump(table, open(out, "w"), indent=1)
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1])
