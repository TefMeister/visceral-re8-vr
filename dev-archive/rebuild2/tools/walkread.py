#!/usr/bin/env python3
"""walkread.py -- rebuild 2 (2026-11-26, RE8-091): reads a walk file the plugin's recorder wrote (native/src/rec.h)
and COUNTS what Tefa saw: "legs glitchy when walking ... teleporty ... jittery"; his clip, frame by frame: the knee
lifts for about ten frames, then in ONE frame the leg is down and the lift starts over, about four times a second;
the hand holds and jumps.

    python walkread.py                  the newest walk file in the game's data folder
    python walkread.py <walk.csv>       that file
    python walkread.py all              one summary line per walk file (the halving test: one file per start)
    python walkread.py selftest         made-up walks with a known answer (a clean walk must count 0)

What it counts, only over the pictures in which the player walks (faster than WALK_MPS):
  motion restarts   the walk motion's frame number going BACK while the same motion plays and it was not at its end
                    (a motion that loops goes back only at its end: that is not counted)
  leg snaps         a foot or knee moving, in the player's own space, further in one picture than SNAP_M and several
                    times further than in the pictures before it
  body snaps        the same for the hip (the whole body moved, not a leg)
  hand holds/jumps  the drawn hand standing still in the head's space while the controller moved, then jumping
and what each leg snap happened together with (the same picture or the one before or after): a motion restart, a new
motion, the stick handed to the game changing, a room step starting or ending, the loader's cutscene flag changing, a
body snap, a long picture. That is the pointer to the cause. It also prints the lean fix's numbers per stop.
Reads only; needs nothing but Python.
"""
import csv
import glob
import math
import os
import random
import statistics
import sys

WALK_MPS = 0.5          # faster than this is walking
SNAP_M = 0.04           # a foot or knee: this far in one picture ...
SNAP_TIMES = 4.0        # ... and this many times its usual step over the pictures before
HIP_SNAP_M = 0.03
HOLD_HAND_M = 0.001     # the drawn hand moved less than this ...
HOLD_REAL_M = 0.004     # ... while the controller moved more than this: a held picture
JUMP_HAND_M = 0.03      # the drawn hand moved this far in one picture ...
JUMP_TIMES = 4.0        # ... and this many times what the controller did
STICK_CHANGE = 0.2
LONG_PICTURE = 1.8      # a picture this many times the usual length
LEGS = ("L_foot", "R_foot", "L_knee", "R_knee")
GAME_DIRS = (r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE",)


def folder():
    for g in GAME_DIRS:
        d = os.path.join(g, "reframework", "data", "visceral_re8", "walkrec")
        if os.path.isdir(d):
            return d
    return None


def load(path):
    with open(path, newline="", encoding="utf-8", errors="replace") as f:
        first = f.readline().strip()
        rows = []
        for r in csv.DictReader(f):
            try:
                rows.append({k: float(v) for k, v in r.items() if k is not None and v not in (None, "")})
            except ValueError:
                continue                      # a line cut off when the game closed
    return first, rows


def vec(r, name):
    return (r.get(name + "_x", 0.0), r.get(name + "_y", 0.0), r.get(name + "_z", 0.0))


def dist(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def frame_key(rows):
    """the motion frame comes as a float on some loader builds and as a double on others; take the one that reads
    as a frame number (it changes, and stays within 0 .. a few thousand)"""
    best = None
    for key in ("m0_frame", "m0_frame_d"):
        vals = [r.get(key, -1.0) for r in rows]
        ok = [v for v in vals if 0.0 <= v < 5000.0]
        if len(ok) > len(vals) * 0.8 and len(set(round(v, 1) for v in ok)) > 5:
            best = best or key
    return best


def analyse(rows):
    out = {"pictures": len(rows)}
    if len(rows) < 30:
        return out
    dts = [r["dt_ms"] for r in rows]
    usual_dt = statistics.median(dts)
    out["seconds"] = sum(dts) / 1000.0
    out["rate"] = 1000.0 / usual_dt if usual_dt > 0 else 0.0
    walking = [r["speed"] > WALK_MPS and int(r["flags"]) & 8 != 0 for r in rows]
    out["walk_s"] = sum(d for d, w in zip(dts, walking) if w) / 1000.0
    out["joints_missing"] = [j for j in LEGS + ("hip",) if all(abs(r.get(j + "_x", 0.0)) + abs(r.get(j + "_y", 0.0)) < 1e-6 for r in rows)]
    key = frame_key(rows)
    out["motion_known"] = key is not None

    marks = {k: set() for k in ("restart", "new motion", "stick change", "room step", "cutscene flag", "body snap", "long picture")}
    snaps = {j: [] for j in LEGS}
    holds = {"L": 0, "R": 0}
    jumps = {"L": 0, "R": 0}
    still_holds = {"L": 0, "R": 0}
    for i in range(1, len(rows)):
        a, b = rows[i - 1], rows[i]
        fa, fb = int(a["flags"]), int(b["flags"])
        if key is not None and a.get("m0_id") == b.get("m0_id") and a.get("m0_bank") == b.get("m0_bank"):
            end = b.get("m0_end", -1.0)
            went_back = b[key] < a[key] - 1.5
            at_end = end > 0 and a[key] > end - 3.0
            if went_back and not at_end:
                marks["restart"].add(i)
        if a.get("m0_id") != b.get("m0_id") or a.get("m0_bank") != b.get("m0_bank"):
            marks["new motion"].add(i)
        if abs(b["stick_x"] - a["stick_x"]) + abs(b["stick_y"] - a["stick_y"]) > STICK_CHANGE:
            marks["stick change"].add(i)
        if (fa ^ fb) & 16:
            marks["room step"].add(i)
        if (fa ^ fb) & 1:
            marks["cutscene flag"].add(i)
        if dist(vec(a, "hip"), vec(b, "hip")) > HIP_SNAP_M:
            marks["body snap"].add(i)
        if b["dt_ms"] > usual_dt * LONG_PICTURE:
            marks["long picture"].add(i)
        for side in ("L", "R"):
            hand, real = dist(vec(a, "g" + side), vec(b, "g" + side)), dist(vec(a, "c" + side), vec(b, "c" + side))
            asleep = fb & (32 if side == "L" else 64)
            if asleep or not fb & 2:
                continue
            if hand < HOLD_HAND_M and real > HOLD_REAL_M:
                if walking[i]:
                    holds[side] += 1
                else:
                    still_holds[side] += 1
            if hand > JUMP_HAND_M and hand > real * JUMP_TIMES and walking[i]:
                jumps[side] += 1
    for j in LEGS:
        steps = [dist(vec(rows[i - 1], j), vec(rows[i], j)) for i in range(1, len(rows))]
        for i in range(6, len(steps)):
            usual = statistics.median(steps[i - 6:i])
            if walking[i + 1] and steps[i] > SNAP_M and steps[i] > usual * SNAP_TIMES:
                snaps[j].append(i + 1)
    walk_s = max(out["walk_s"], 1e-6)
    out["restarts"] = len([i for i in marks["restart"] if walking[i]])
    out["restarts_per_s"] = out["restarts"] / walk_s
    out["snaps"] = {j: len(v) for j, v in snaps.items()}
    feet = sorted(set(snaps["L_foot"]) | set(snaps["R_foot"]))
    out["leg_snaps_per_s"] = len(feet) / walk_s
    out["body_snaps_per_s"] = len([i for i in marks["body snap"] if walking[i]]) / walk_s
    out["holds"], out["jumps"], out["still_holds"] = holds, jumps, still_holds
    out["hand_jumps_per_s"] = (jumps["L"] + jumps["R"]) / walk_s
    every = sorted(set(i for v in snaps.values() for i in v))
    out["with"] = {}
    for name, where in marks.items():
        near = sum(1 for i in every if i in where or i - 1 in where or i + 1 in where)
        out["with"][name] = (near, len(every))
    gaps = [(feet[k + 1] - feet[k]) * usual_dt / 1000.0 for k in range(len(feet) - 1) if feet[k + 1] - feet[k] < 200]
    out["snap_gap_s"] = statistics.median(gaps) if gaps else 0.0
    # the lean fix: each stop (walking, then standing), the nearest the neck came and the most asked
    stops, i = [], 1
    while i < len(rows):
        if rows[i - 1]["speed"] > 1.0 and rows[i]["speed"] <= 1.0:
            seg = rows[i:i + int(out["rate"] * 1.2) + 1]
            if seg and min(r["speed"] for r in seg) < 0.1:
                stops.append((min(r["neck_behind"] for r in seg), max(r["lean_ask"] for r in seg), max(r["lean_applied"] for r in seg)))
                i += len(seg)
                continue
        i += 1
    out["stops"] = stops
    out["standing_cm"] = max((r["lean_standing"] for r in rows), default=0.0) * 100.0
    moved = [r for r in rows if r["lean_applied"] > 0.01]
    out["lean_used"] = len(moved)
    return out


def say(first, o, name=""):
    lines = []
    if name:
        lines.append(name)
    lines.append(first.lstrip("# "))
    if o["pictures"] < 30:
        lines.append("too short to read (%d pictures)" % o["pictures"])
        return lines
    lines.append("%.0f s recorded at %.0f pictures a second; %.0f s of it walking" % (o["seconds"], o["rate"], o["walk_s"]))
    if o["joints_missing"]:
        lines.append("!! NOT RECORDED (the joint was not found, see the game's log line \"recorders: joints\"): " + ", ".join(o["joints_missing"]))
    if o["walk_s"] < 3.0:
        lines.append("less than 3 s of walking: the counts below mean little")
    lines.append("THE LEGS, while walking:")
    if o["motion_known"]:
        lines.append("  walk motion starting over mid-way: %d times = %.1f a second" % (o["restarts"], o["restarts_per_s"]))
    else:
        lines.append("  the walk motion's frame could not be read (no count of restarts)")
    lines.append("  a foot snapping in one picture: %.1f a second (left foot %d, right foot %d, left knee %d, right knee %d)" % (
        o["leg_snaps_per_s"], o["snaps"]["L_foot"], o["snaps"]["R_foot"], o["snaps"]["L_knee"], o["snaps"]["R_knee"]))
    if o["snap_gap_s"] > 0:
        lines.append("  usual time from one snap to the next: %.2f s" % o["snap_gap_s"])
    lines.append("  the whole body snapping (hip): %.1f a second" % o["body_snaps_per_s"])
    total = max((n for _, n in o["with"].values()), default=0)
    if total:
        lines.append("  of the %d leg snaps, how many came together with:" % total)
        for name_, (near, n) in sorted(o["with"].items(), key=lambda kv: -kv[1][0]):
            lines.append("    %-14s %3d  (%.0f%%)" % (name_, near, 100.0 * near / n))
    lines.append("THE HANDS, while walking: held pictures left %d, right %d; jumps left %d, right %d (%.1f jumps a second); held while standing: left %d, right %d" % (
        o["holds"]["L"], o["holds"]["R"], o["jumps"]["L"], o["jumps"]["R"], o["hand_jumps_per_s"], o["still_holds"]["L"], o["still_holds"]["R"]))
    lines.append("THE BODY AT A STOP: %d stops; standing distance learned: %s" % (
        len(o["stops"]), ("%.0f cm" % o["standing_cm"]) if o["standing_cm"] > 0 else "not yet"))
    for nearest, ask, used in o["stops"][:12]:
        lines.append("    the neck came to %.0f cm behind the eyes; the fix asked for up to %.0f cm%s" % (
            nearest * 100.0, ask * 100.0, (" and %.0f cm was used" % (used * 100.0)) if used > 0.005 else " (measuring only)"))
    verdict = "CLEAN: no leg fault counted" if o["leg_snaps_per_s"] < 0.3 and o["restarts_per_s"] < 0.3 else \
        "THE FAULT IS IN THIS RUN: %.1f leg snaps and %.1f motion restarts a second" % (o["leg_snaps_per_s"], o["restarts_per_s"])
    lines.append("VERDICT: " + verdict)
    return lines


def one_line(first, o):
    off = first[first.find("off="):] if "off=" in first else "?"
    if o["pictures"] < 30 or o.get("walk_s", 0) < 3.0:
        return "%s: not enough walking" % off
    return "%s: %.0f s walking, %.1f leg snaps/s, %.1f motion restarts/s, %.1f body snaps/s, %.1f hand jumps/s" % (
        off, o["walk_s"], o["leg_snaps_per_s"], o["restarts_per_s"], o["body_snaps_per_s"], o["hand_jumps_per_s"])


# ---- selftest: made-up walks -----------------------------------------------------------------------------------
def made_up(seconds=20.0, restart_every=0, stale_hand=0, hip_jump_every=0, seed=1):
    rnd = random.Random(seed)
    rows, frame, t, phase = [], 0.0, 0.0, 0.0
    hand = None
    for i in range(int(seconds * 90)):
        walking = i > 180
        if walking:
            frame += 0.67
            phase += 0.67
            if frame >= 60.0:
                frame -= 60.0                     # the motion's own loop: at its end, never counted
            if restart_every and i % restart_every == 0:
                frame, phase = 0.0, 0.0           # the fault: the motion and the leg start over mid-way
        swing = math.sin(phase / 60.0 * 2 * math.pi)
        lift = max(0.0, swing) * 0.18
        r = {"t_ms": t * 1000, "dt_ms": 11.1, "flags": 8 | 2, "speed": 2.0 if walking else 0.0, "head_off_deg": 0.0,
             "stick_x": 0.0, "stick_y": 1.0 if walking else 0.0, "px": 0.0, "pz": t * 2.0, "pyaw_deg": 0.0,
             "m0_bank": 1, "m0_id": 30 if walking else 2, "m0_frame": frame, "m0_frame_d": -1.0, "m0_end": 60.0,
             "m1_bank": 0, "m1_id": 0, "m1_frame": -1, "m1_frame_d": -1, "m1_end": -1}
        hip_x = 0.05 if hip_jump_every and (i // hip_jump_every) % 2 else 0.0
        pos = {"hip": (hip_x, 0.95, 0.0), "L_foot": (-0.1, 0.08 + lift, 0.25 * swing), "R_foot": (0.1, 0.08 + max(0.0, -swing) * 0.18, -0.25 * swing),
               "L_knee": (-0.1, 0.5 + lift * 0.5, 0.15 * swing), "R_knee": (0.1, 0.5, -0.15 * swing)}
        real = (0.2 + 0.15 * math.sin(i * 0.11), -0.3 + 0.02 * math.sin(i * 0.07), -0.35 + rnd.uniform(-0.0005, 0.0005) + 0.03 * math.sin(i * 0.05))
        if stale_hand and walking and i % stale_hand != 0 and hand is not None:
            pass                                   # the drawn hand holds ...
        else:
            hand = real                            # ... and jumps to the controller every stale_hand pictures
        for name, p in pos.items():
            r[name + "_x"], r[name + "_y"], r[name + "_z"] = p
        for name, p in (("gL", real), ("gR", hand), ("cL", real), ("cR", real)):
            r[name + "_x"], r[name + "_y"], r[name + "_z"] = p
        r.update({"neck_behind": 0.16, "lean_raw": 0.16, "lean_standing": 0.16, "lean_ask": 0.0, "lean_applied": 0.0, "down": 0.0})
        rows.append(r)
        t += 0.0111
    return rows


def selftest():
    bad = 0

    def check(what, ok, got):
        nonlocal bad
        print("%s %s (%s)" % ("ok  " if ok else "FAIL", what, got))
        bad += 0 if ok else 1

    clean = analyse(made_up())
    check("a clean walk: no leg snap", clean["leg_snaps_per_s"] == 0, clean["leg_snaps_per_s"])
    check("a clean walk: no motion restart (the loop at its end is not one)", clean["restarts"] == 0, clean["restarts"])
    check("a clean walk: no hand jump", clean["jumps"]["R"] == 0 and clean["holds"]["R"] == 0, clean["jumps"])
    fault = analyse(made_up(restart_every=22))            # about four a second at 90 pictures a second
    check("a walk starting over every 22 pictures: about 4 restarts a second", 3.5 < fault["restarts_per_s"] < 4.6, round(fault["restarts_per_s"], 2))
    check("... and the feet snap with it", fault["leg_snaps_per_s"] > 2.5, round(fault["leg_snaps_per_s"], 2))
    near, n = fault["with"]["restart"]
    check("... and the snaps are counted as coming with the restarts", n > 0 and near / n > 0.9, "%d of %d" % (near, n))
    check("... about 0.24 s apart", 0.2 < fault["snap_gap_s"] < 0.3, round(fault["snap_gap_s"], 3))
    hands = analyse(made_up(stale_hand=9))
    check("a drawn hand renewed every 9th picture: holds and jumps counted on the right, none on the left",
          hands["holds"]["R"] > 500 and hands["jumps"]["R"] > 50 and hands["holds"]["L"] == 0 and hands["jumps"]["L"] == 0,
          "holds %s jumps %s" % (hands["holds"], hands["jumps"]))
    body = analyse(made_up(hip_jump_every=30))
    check("a hip jumping 5 cm every 30 pictures: body snaps counted, no leg snap", body["body_snaps_per_s"] > 2.0 and body["leg_snaps_per_s"] == 0,
          round(body["body_snaps_per_s"], 2))
    print("walkread selftest: all right" if bad == 0 else "walkread selftest: %d FAILED" % bad)
    return 1 if bad else 0


def main(argv):
    if len(argv) > 1 and argv[1] == "selftest":
        return selftest()
    if len(argv) > 1 and argv[1] not in ("all",):
        paths = [argv[1]]
    else:
        d = folder()
        paths = sorted(glob.glob(os.path.join(d, "walk-*.csv"))) if d else []
        if not paths:
            print("no walk file yet: the recorder writes one per headset session")
            return 1
        if len(argv) < 2:
            paths = paths[-1:]
    for p in paths:
        first, rows = load(p)
        o = analyse(rows)
        if len(argv) > 1 and argv[1] == "all":
            print("%s  %s" % (os.path.basename(p), one_line(first, o)))
        else:
            print("\n".join(say(first, o, os.path.basename(p))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
