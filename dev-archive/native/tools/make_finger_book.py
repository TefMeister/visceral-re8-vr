"""make_finger_book.py -- cut every gun's finger takes into the clips the native plugin plays on the docked hands (2026-11-04).

Step 2 of Tefa's 2026-11-02 ask ("record every default game reloading, grip and docked pose for hands and fingers ... use these
hand grip poses when gripping weapons in VR"): the takes from lua/visceral_re8_finger_rec.lua (every finger joint's local
rotation, every frame, plus the motion each layer plays) become one clip per gun and EVENT, named the way shellclip.cpp
looks them up: reframework/data/visceral_re8/clips/<gun>_<event>.csv. A clip holds the joints of the hand(s) whose fingers
actually move in that part of the take (the header names them: L_IndexF1.x ... R_Thumb3.w), so the player moves only those.

Events, from what the motion layers say (player layer 1):
  round_in   one cycle of the per-round motion 2512 (the shotguns, the revolvers, the Rocket Pistol): the hand that pushes it in
  rack       the closing motion 2513 (the pump on the shotguns, the cover on the revolvers); written, not yet played
  mag_out    the first half of the magazine reload 2500: the hand on the magazine, pulling it out, letting go
  mag_in     the second half: the new magazine in; split at the deepest finger opening after the fullest grasp
  reload     the whole 2500 on a gun without a magazine (the GM 79); written, not yet played
The clips are the game's own animation data: written to the game's data folder only, never to GitHub.

    python make_finger_book.py [--takes DIR] [--out DIR] [--gun ri3046 ...] [--dry]
"""
import argparse
import csv
import glob
import math
import os

FINGERS = ["IndexF1", "IndexF2", "IndexF3", "MiddleF1", "MiddleF2", "MiddleF3", "RingF1", "RingF2", "RingF3",
           "PinkyF1", "PinkyF2", "PinkyF3", "Thumb1", "Thumb2", "Thumb3"]
TAKES = r"D:\claude video game stuff\finger-takes\2026-11-02"
OUT = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE\reframework\data\visceral_re8\clips"
MAG_GUNS = {"ri3040", "ri3046", "ri3047", "ri3050", "ri3122", "ri3124", "ri3042", "ri3049", "ri3125", "ri3048"}
MOVE_DEG = 10.0    # a hand is in a clip when one of its finger joints turns at least this much inside the segment
SPLIT_SKIP = {"ri3042"}   # the F2 Rifle: the bolt (right hand) comes first and the fore-end hold curls more than the magazine grasp,
                          # so the grasp / open rule cannot find the split; written whole as "reload" until cut by hand
LAYER = "player.1"


def layers(cell):
    out = {}
    for m in cell.split("|"):
        p = m.split(":")
        if len(p) == 4:
            out[p[0]] = (p[2], float(p[3]))
    return out


def angle(q):
    return math.degrees(2 * math.acos(max(-1.0, min(1.0, abs(q[3])))))


class Take:
    def __init__(self, path):
        rows = list(csv.reader(open(path, newline="")))
        self.head, self.rows = rows[0], rows[1:]
        self.cols = {s: [[self.head.index(f"player:{s}{f}.{c}") for c in "xyzw"] for f in FINGERS] for s in ("L_", "R_")}
        self.motion = []
        for r in self.rows:
            L = layers(r[3]).get(LAYER)
            self.motion.append((L[0], L[1]) if L else ("-", -1))

    def curl(self, i, side):
        return sum(angle([float(self.rows[i][k]) for k in c4]) for c4 in self.cols[side][:12]) / 12

    def segments(self, motion):
        """[(a, b)] frame ranges where MOTION plays, a new range at every frame-counter restart"""
        out, a, last = [], None, None
        for i, (m, fr) in enumerate(self.motion):
            if m != motion:
                if a is not None:
                    out.append((a, i))
                a, last = None, None
                continue
            if a is None:
                a = i
            elif last is not None and fr < last - 1.0:
                out.append((a, i))
                a = i
            last = fr
        if a is not None:
            out.append((a, len(self.motion)))
        return out

    def joint_range(self, a, b, side):
        """the widest turn any one finger joint of that hand makes inside the segment (degrees), thumb included"""
        worst = 0.0
        for c4 in self.cols[side]:
            angs = [angle([float(self.rows[i][k]) for k in c4]) for i in range(a, b)]
            worst = max(worst, max(angs) - min(angs))
        return worst

    def hands(self, a, b):
        return [s for s in ("L_", "R_") if self.joint_range(a, b, s) >= MOVE_DEG]

    def write(self, out, a, b, sides):
        names = [f"{s}{f}" for s in sides for f in FINGERS]
        cols = [c4 for s in sides for c4 in self.cols[s]]
        t0 = float(self.rows[a][0])
        with open(out, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["t"] + [f"{n}.{c}" for n in names for c in "xyzw"])
            for r in self.rows[a:b]:
                w.writerow([f"{float(r[0]) - t0:.4f}"] + [r[i] for c4 in cols for i in c4])
        return float(self.rows[b - 1][0]) - t0

    def split_mag(self, a, b):
        """the frame between the magazine coming out and the new one going in: the deepest left-hand opening after the
        fullest grasp (the LEMI: grasp 70 deg at 1.66 s, open 15 deg at 1.99 s, the new magazine 24-38 deg after)"""
        cs = [self.curl(i, "L_") for i in range(a, b)]
        sm = [sum(cs[max(0, k - 2):k + 3]) / len(cs[max(0, k - 2):k + 3]) for k in range(len(cs))]
        gmax, gmin = max(sm), min(sm)
        mid = (gmax + gmin) / 2
        k = next((i for i, v in enumerate(sm) if v >= gmax - 0.1 * (gmax - gmin)), None)   # the first full grasp
        if k is None:
            return None
        peak = k
        while k < len(sm) and sm[k] >= mid:   # hold the grasp until the hand opens past half way
            k += 1
        while k + 1 < len(sm) and sm[k + 1] <= sm[k]:   # down to the bottom of that opening
            k += 1
        if k >= len(sm) - 5:
            return None
        return a + k, sm[peak], sm[k]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--takes", default=TAKES)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--gun", nargs="*")
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    if not a.dry:
        os.makedirs(a.out, exist_ok=True)
    for take in sorted(glob.glob(os.path.join(a.takes, "reload_full__*.csv"))):
        gun = os.path.basename(take).split("__")[1].split("_")[0]
        if a.gun and gun not in a.gun:
            continue
        T = Take(take)
        plan = []   # (event, a, b, note)
        r2512 = T.segments("2512")
        if r2512:
            cyc = r2512[1] if len(r2512) > 1 else r2512[0]   # the second cycle starts and ends inside the loop
            plan.append(("round_in", *cyc, f"cycle {1 if len(r2512) > 1 else 0} of {len(r2512)}"))
        r2513 = T.segments("2513")
        if r2513:
            plan.append(("rack", *r2513[0], "the closing motion"))
        r2500 = T.segments("2500")
        if r2500:
            s, e = r2500[0]
            if gun in MAG_GUNS and gun not in SPLIT_SKIP:
                sp = T.split_mag(s, e)
                if sp:
                    k, pk, tr = sp
                    plan.append(("mag_out", s, k, f"grasp {pk:.0f} deg, open {tr:.0f} deg at frame {k - s}"))
                    plan.append(("mag_in", k, e, ""))
                else:
                    plan.append(("reload", s, e, "no split found"))
            else:
                plan.append(("reload", s, e, "no magazine"))
        for ev, s, e, note in plan:
            sides = T.hands(s, e)
            if not sides:
                print(f"{gun} {ev}: no hand moves in frames {s}-{e}: not written")
                continue
            out = os.path.join(a.out, f"{gun}_{ev}.csv")
            secs = float(T.rows[e - 1][0]) - float(T.rows[s][0])
            if not a.dry:
                secs = T.write(out, s, e, sides)
            print(f"{gun} {ev}: {e - s} frames, {secs:.2f} s, hands {'+'.join(x[0] for x in sides)}  {note}")


if __name__ == "__main__":
    main()
