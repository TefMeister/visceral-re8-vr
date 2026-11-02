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


RE2_FINGERS = [f"l_hand_{f}" for f in ("index_0", "index_1", "index_2", "middle_0", "middle_1", "middle_2", "ring_0", "ring_1",
                                         "ring_2", "ring_3", "little_0", "little_1", "little_2", "little_3", "thumb_0", "thumb_1", "thumb_2")]


def write(out, pick, names, cols):
    t0 = float(pick[0][0])
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["t"] + [f"{n}.{c}" for n in names for c in "xyzw"])
        for r in pick:
            w.writerow([f"{float(r[0]) - t0:.4f}"] + [r[i] for c4 in cols for i in c4])


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
    ap.add_argument("--window", default="", help="T0,T1 seconds: cut this time window instead of a motion cycle (RE2 / RE3 play a"
                    " whole reload as one motion, 2026-11-02)")
    ap.add_argument("--re2", action="store_true", help="RE2 / RE3 takes: joints l_hand_index_0.., columns without a transform prefix")
    a = ap.parse_args()
    rows = list(csv.reader(open(a.take, newline="")))
    head, rows = rows[0], rows[1:]
    if a.window:
        t0, t1 = (float(x) for x in a.window.split(","))
        r0 = next(float(r[0]) for r in rows if r[2] == "true") if any(r[2] == "true" for r in rows) else float(rows[0][0])
        pick = [r for r in rows if t0 <= float(r[0]) - r0 <= t1]
        names = RE2_FINGERS if a.re2 else [f"{a.side}{f}" for f in FINGERS]
        cols = [[head.index(f"{n}.{c}" if a.re2 else f"{a.transform}:{n}.{c}") for c in "xyzw"] for n in names]
        write(a.out, pick, names, cols)
        print(f"window {t0:.2f}-{t1:.2f} s after the reload began: {len(pick)} frames, {len(names)} joints -> {a.out}")
        return
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
