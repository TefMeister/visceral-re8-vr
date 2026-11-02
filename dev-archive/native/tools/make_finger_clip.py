"""make_finger_clip.py -- cut one cycle of a game motion's finger movement out of a finger take (2026-11-02).

Tefa, 2026-11-02: "put the games original finger movements into inserting a shell into w870 shotgun, so that in the
activation zone, hand can still be moved, but the finger animation of a shell being inserted plays when the shell goes in".

The takes come from lua/visceral_re8_finger_rec.lua (every finger joint's local rotation, every frame, plus the motion
playing on each layer). A looping motion (the W870's one-shell-in, motion 2512) restarts its frame counter at every
shell; this cuts out one whole cycle (the second, so it starts and ends inside the loop, not at its edges) and writes it
as a clip shellclip.cpp plays: a header "t,<joint>.x,.y,.z,.w,..." and one row per recorded frame, time from 0.

The clip is the game's own animation data, so it is written to the game's data folder, never to GitHub.

    python make_finger_clip.py TAKE.csv MOTION OUT.csv [--side L_] [--transform player] [--cycle 1] [--layer 1]
"""
import argparse
import csv

FINGERS = ["IndexF1", "IndexF2", "IndexF3", "MiddleF1", "MiddleF2", "MiddleF3", "RingF1", "RingF2", "RingF3",
           "PinkyF1", "PinkyF2", "PinkyF3", "Thumb1", "Thumb2", "Thumb3"]


def layers(cell):
    out = {}
    for m in cell.split("|"):
        p = m.split(":")
        if len(p) == 4:
            out[p[0]] = (p[2], float(p[3]))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("take")
    ap.add_argument("motion")
    ap.add_argument("out")
    ap.add_argument("--side", default="L_")
    ap.add_argument("--transform", default="player")
    ap.add_argument("--cycle", type=int, default=1, help="which cycle of the loop (0 = the first)")
    ap.add_argument("--layer", default="1")
    a = ap.parse_args()
    rows = list(csv.reader(open(a.take, newline="")))
    head, rows = rows[0], rows[1:]
    lay = f"{a.transform}.{a.layer}"
    cycles, cur, last = [], [], None
    for r in rows:
        L = layers(r[3]).get(lay)
        if not L or L[0] != a.motion:
            if cur:
                cycles.append(cur)
            cur, last = [], None
            continue
        if last is not None and L[1] < last - 1.0:   # the frame counter went back: a new cycle
            cycles.append(cur)
            cur = []
        cur.append(r)
        last = L[1]
    if cur:
        cycles.append(cur)
    if not cycles:
        raise SystemExit(f"motion {a.motion} never plays on layer {lay} in this take")
    pick = cycles[min(a.cycle, len(cycles) - 1)]
    names = [f"{a.side}{f}" for f in FINGERS]
    cols = []
    for n in names:
        base = f"{a.transform}:{n}"
        cols.append([head.index(f"{base}.{c}") for c in "xyzw"])
    t0 = float(pick[0][0])
    with open(a.out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["t"] + [f"{n}.{c}" for n in names for c in "xyzw"])
        for r in pick:
            w.writerow([f"{float(r[0]) - t0:.4f}"] + [r[i] for c4 in cols for i in c4])
    print(f"{len(cycles)} cycles of motion {a.motion}; wrote cycle {min(a.cycle, len(cycles) - 1)}: {len(pick)} frames, "
          f"{float(pick[-1][0]) - t0:.2f} s, {len(names)} joints -> {a.out}")


if __name__ == "__main__":
    main()
