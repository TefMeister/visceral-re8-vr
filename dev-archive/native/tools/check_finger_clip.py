"""check_finger_clip.py -- did the hand's fingers follow a clip? (2026-11-04)

While shellclip.cpp plays a clip, the finger recorder (lua/visceral_re8_finger_rec.lua) records what the joints actually
held. This compares the two: for every recorded frame, the nearest clip frame (mean angle between the recorded and the clip
rotation over the clip's joints, degrees). While the clip plays the distance should drop to a few degrees; before and after
it is whatever the hand's own pose is from the clip (tens of degrees). Prints the distance over time and a verdict.

    python check_finger_clip.py TAKE.csv CLIP.csv [--prefix player]
"""
import argparse
import csv
import math


def angle_between(a, b):
    d = abs(sum(x * y for x, y in zip(a, b)))
    return math.degrees(2 * math.acos(max(-1.0, min(1.0, d))))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("take")
    ap.add_argument("clip")
    ap.add_argument("--prefix", default="player")
    a = ap.parse_args()
    clip = list(csv.reader(open(a.clip, newline="")))
    chead, crows = clip[0], clip[1:]
    names = [h[:-2] for h in chead[1::4]]
    take = list(csv.reader(open(a.take, newline="")))
    thead, trows = take[0], take[1:]
    tcols = [[thead.index(f"{a.prefix}:{n}.{c}") for c in "xyzw"] for n in names]
    ccols = [[chead.index(f"{n}.{c}") for c in "xyzw"] for n in names]
    cq = [[[float(r[i]) for i in c4] for c4 in ccols] for r in crows]
    best_run, run, out = 0, 0, []
    for r in trows:
        tq = [[float(r[i]) for i in c4] for c4 in tcols]
        d = min(sum(angle_between(x, y) for x, y in zip(tq, cf)) / len(names) for cf in cq)
        out.append((float(r[0]), d))
        run = run + 1 if d < 4.0 else 0
        best_run = max(best_run, run)
    step = max(1, len(out) // 60)
    print(" ".join(f"{t:.1f}s:{d:.0f}" for t, d in out[::step]))
    close = sum(1 for _, d in out if d < 4.0)
    print(f"{len(names)} joints; {close} of {len(out)} recorded frames within 4 deg of a clip frame; longest run {best_run} frames; "
          f"nearest overall {min(d for _, d in out):.1f} deg, farthest {max(d for _, d in out):.1f} deg")
    print("VERDICT:", "the fingers followed the clip" if best_run >= 10 else "the fingers did NOT follow the clip")


if __name__ == "__main__":
    main()
