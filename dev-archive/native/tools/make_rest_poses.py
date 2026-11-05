"""make_rest_poses.py -- every gun's RESTING hand poses for our docked hands, cut from the game's own finger takes (2026-11-05).

Tefa 2026-11-02: "default hand animations, just the hand and fingers, so wrists are not locked and hands can still be naturally
moved in vr ... use these hand grip poses when gripping weapons in VR". The moving parts (shell in, magazine out / in) play as
clips (make_finger_book.py, shellclip.cpp). This is the STILL part: the pose a docked hand rests in between those clips, one
per gun and spot, written as Hand Poser files (reframework/data/hand_poser/guns/<gun>_Inventory[ @ <spot>].json), which the
in-game hand_poser.lua loads whenever the gun or the hand's spot changes, and which Tefa fine-tunes in the Hand Poser window.

Where each pose comes from (the takes of lua/visceral_re8_finger_rec.lua, player layer 1 motions):
  the gun's own pose, "@ handle"   the two-handed hold: the middle of motion 2100 (the hands on the gun after a reload; the
                                   draw_idle takes of the guns put in hand by `equip` show only the relaxed curl)
  "@ magazine", "@ insert point"   the fullest left grasp inside 2500 after the hand first opens to reach, before it returns
                                   to the hold (the LEMI: 70 deg at 1.2 s; the F2: its 39 deg plateau, the magazine is wide)
  "@ slide" (pump guns)            the grip inside 2513 that works the pump (after the shell is let go; the W870's is its hold)
  "@ slide" (every other gun)      BORROWED: the W870's hand on its pump (no gun's reload has the left hand on a slide)
  "@ rounds from the pouch",
  "@ slide from the left"          a shell in the hand: the start of the second 2512 cycle (the shell port shares spot 8 with
                                   "slide from the left"; the revolvers load with the RIGHT hand in the game, so their left
                                   shell pose is BORROWED from the W870 too)
  "@ drum" (revolvers)             the left hand holding the gun by the cylinder: the middle of a 2512 cycle
  "right hand on the cover"        the right hand with a round, about to push it in: the start of a 2512 cycle (right joints)
  "right hand on the bolt" (F2)    the right hand's fullest curl in the first 1.2 s of 2500 (the bolt comes first)
Angles are the engine's own local Euler angles (degrees), the convention measured live with autorun zz_euler_probe.lua
(`--fit euler_probe.csv` prints the fit; EULER below is the result).

Existing files: ALL are copied to the archive first. A file that is the only one of its kind is Tefa's and is KEPT; of a set
of identical files the OLDEST is kept (the original) and the copies are replaced; a copy of "no gun.json" is replaced.

    python make_rest_poses.py [--dry] [--gun ri3046 ...] [--fit euler_probe.csv] [--takes DIR] [--out DIR] [--app DIR] [--archive DIR]
"""
import argparse
import csv
import datetime
import glob
import hashlib
import json
import math
import os
import shutil

FINGERS = ["IndexF1", "IndexF2", "IndexF3", "MiddleF1", "MiddleF2", "MiddleF3", "RingF1", "RingF2", "RingF3",
           "PinkyF1", "PinkyF2", "PinkyF3", "Thumb1", "Thumb2", "Thumb3"]
CURL = 12   # the first twelve (not the thumb) measure how closed a hand is
TAKES = r"D:\claude video game stuff\finger-takes\2026-11-02"
GAME = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE\reframework\data"
OUT = os.path.join(GAME, "hand_poser", "guns")
APP = os.path.join(os.environ.get("APPDATA", ""), "HandPoserVR", "re8", "guns")   # the Hand Poser window's own copies
HERE = os.path.dirname(os.path.abspath(__file__))
ARCHIVE = os.path.join(HERE, "..", "..", "hand-poses", "archive")
LAYER = "player.1"
EULER = "YXZ"   # measured 2026-11-05 with zz_euler_probe.lua: q = qY * qX * qZ, 12000 samples, 0.0000 deg error

PISTOL_MAG = ["ri3040", "ri3046", "ri3047", "ri3050", "ri3122", "ri3124"]
LONG_MAG = ["ri3042", "ri3049", "ri3125", "ri3048"]
PUMP = ["ri3021", "ri3036"]
ROCKET = ["ri3115"]
REVOLVER = ["ri3008", "ri3116"]
LAUNCHER = ["ri3023"]
WRAP_DONOR = "ri3021"   # the W870: its hand on the pump, and its hand with a shell, lent to the guns without their own


# ---- maths ------------------------------------------------------------------------------------------------------------
def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


def qnorm(q):
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    q = tuple(c / n for c in q)
    return q if q[3] >= 0 else tuple(-c for c in q)


def qaxis(axis, rad):
    s, c = math.sin(rad / 2), math.cos(rad / 2)
    return {"X": (s, 0, 0, c), "Y": (0, s, 0, c), "Z": (0, 0, s, c)}[axis]


def qangle(a, b):
    d = abs(sum(x * y for x, y in zip(a, b)))
    return math.degrees(2 * math.acos(max(-1.0, min(1.0, d))))


def curl_of(q):
    return math.degrees(2 * math.acos(max(-1.0, min(1.0, abs(q[3])))))


def compose(order, e):
    """the quaternion the engine makes of Euler angles e = (x, y, z) radians, for a multiplication order such as 'ZYX'
    (q = qZ * qY * qX: the X turn applied first)"""
    q = (0, 0, 0, 1)
    for ax in order:
        q = qmul(q, qaxis(ax, e["XYZ".index(ax)]))
    return qnorm(q)


def to_matrix(q):
    x, y, z, w = q
    return [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]


def decompose(order, q):
    """Euler angles (x, y, z) radians such that compose(order, e) == q. Tait-Bryan extraction from the rotation matrix,
    R = R[a] R[b] R[c] for order 'abc'; checked by round trip in selftest()."""
    m = to_matrix(q)
    i, j, k = ["XYZ".index(c) for c in order]
    # parity of the axis order: cyclic (XYZ, YZX, ZXY) = +1, anticyclic = -1
    sign = 1.0 if (j - i) % 3 == 1 else -1.0
    sb = max(-1.0, min(1.0, sign * m[i][k]))
    b = math.asin(sb)
    if abs(sb) < 0.9999999:
        a = math.atan2(-sign * m[j][k], m[k][k])
        c = math.atan2(-sign * m[i][j], m[i][i])
    else:   # gimbal lock: the first and last turns share an axis; everything goes into the first
        a = math.atan2(sign * m[k][j], m[j][j])
        c = 0.0
    e = [0.0, 0.0, 0.0]
    e[i], e[j], e[k] = a, b, c
    return tuple(e)


def selftest():
    import random
    random.seed(7)
    for order in ("XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX"):
        worst = 0.0
        for _ in range(500):
            q = qnorm(tuple(random.uniform(-1, 1) for _ in range(4)))
            e = decompose(order, q)
            if abs(math.sin(e["XYZ".index(order[1])])) > 0.999:
                continue
            worst = max(worst, qangle(q, compose(order, e)))
        if worst > 1e-3:
            raise SystemExit(f"selftest: decompose({order}) round trip off by {worst:.4f} deg")


def fit(path):
    """which multiplication order (and sign) turns the engine's Euler angles into its quaternions: the probe's pairs"""
    rows = list(csv.DictReader(open(path, newline="")))
    best = None
    print(f"fit: {len(rows)} joint samples from {os.path.basename(path)}")
    for order in ("XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX"):
        for neg in (1.0, -1.0):
            errs = []
            for r in rows:
                q = qnorm((float(r["qx"]), float(r["qy"]), float(r["qz"]), float(r["qw"])))
                e = (neg * float(r["ex"]), neg * float(r["ey"]), neg * float(r["ez"]))
                errs.append(qangle(q, compose(order, e)))
            errs.sort()
            med, mx = errs[len(errs) // 2], errs[-1]
            print(f"  {order}{' (negated)' if neg < 0 else ''}: median {med:8.4f} deg, worst {mx:8.4f} deg")
            if best is None or med < best[0]:
                best = (med, order, neg)
    print(f"fit: best {best[1]}{' negated' if best[2] < 0 else ''} (median error {best[0]:.4f} deg)")
    return best


# ---- the takes ---------------------------------------------------------------------------------------------------------
def layers(cell):
    out = {}
    for m in cell.split("|"):
        p = m.split(":")
        if len(p) == 4:
            out[p[0]] = (p[2], float(p[3]))
    return out


class Take:
    def __init__(self, path):
        rows = list(csv.reader(open(path, newline="")))
        self.path = path
        self.head, self.rows = rows[0], rows[1:]
        self.cols = {s: [[self.head.index(f"player:{s}{f}.{c}") for c in "xyzw"] for f in FINGERS] for s in ("L_", "R_")}
        self.motion = []
        for r in self.rows:
            L = layers(r[3]).get(LAYER)
            self.motion.append((L[0], L[1]) if L else ("-", -1))
        self.t = [float(r[0]) for r in self.rows]

    def quat(self, i, side, f):
        return qnorm(tuple(float(self.rows[i][k]) for k in self.cols[side][f]))

    def pose(self, i, side):
        return {f"{side}{FINGERS[f]}": self.quat(i, side, f) for f in range(len(FINGERS))}

    def curl(self, i, side):
        return sum(curl_of(self.quat(i, side, f)) for f in range(CURL)) / CURL

    def smooth_curl(self, a, b, side):
        cs = [self.curl(i, side) for i in range(a, b)]
        return [sum(cs[max(0, k - 2):k + 3]) / len(cs[max(0, k - 2):k + 3]) for k in range(len(cs))]

    def segments(self, motion):
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

    def seconds(self, a, b):
        return self.t[min(b, len(self.t) - 1)] - self.t[a]

    def frame_at(self, a, b, secs):
        """the first frame of [a, b) at least `secs` after a"""
        for i in range(a, b):
            if self.t[i] - self.t[a] >= secs:
                return i
        return b - 1

    def grasp_frame(self, a, b, side="L_"):
        """the fullest grasp inside [a, b) after the hand first opens to reach (10 deg under the hold) and before its final
        return to the hold (within 4 deg of the segment's last frame); None when the hand never reaches"""
        sm = self.smooth_curl(a, b, side)
        hold = sm[-1]
        first_open = next((k for k, v in enumerate(sm) if v < hold - 10.0), None)
        if first_open is None:
            return None, "the hand never opened to reach"
        last_active = max(k for k, v in enumerate(sm) if abs(v - hold) > 4.0)
        if last_active <= first_open:
            return None, "no grasp after the reach"
        # the grasp is a local peak the hand lets go of again (drops 8 deg or more before the final return): that keeps out
        # the ramp back to the hold, which on the F2 (a wide magazine, held at 39 deg under a 48 deg hold) is the highest part
        best = None
        for k in range(first_open, last_active + 1):
            if any(sm[m] > sm[k] for m in range(max(first_open, k - 3), min(last_active, k + 3) + 1)):
                continue
            if min(sm[k:last_active + 1]) > sm[k] - 8.0:
                continue
            if best is None or sm[k] > sm[best] + 0.5:
                best = k
        if best is None:
            best = max(range(first_open, last_active + 1), key=lambda i: sm[i])
        k = best
        return a + k, f"grasp {sm[k]:.0f} deg at {self.t[a + k] - self.t[a]:.2f} s (hold {hold:.0f})"

    def peak_frame(self, a, b, side, within_s):
        end = self.frame_at(a, b, within_s)
        sm = self.smooth_curl(a, max(end, a + 6), side)
        k = max(range(len(sm)), key=lambda i: sm[i])
        return a + k, f"peak {sm[k]:.0f} deg at {self.t[a + k] - self.t[a]:.2f} s"


def load_takes(takes_dir, gun):
    out = {}
    for kind in ("reload_full", "draw_idle"):
        m = sorted(glob.glob(os.path.join(takes_dir, f"{kind}__{gun}_*.csv")))
        if m:
            out[kind] = Take(m[-1])
    return out


# ---- the poses of one gun ------------------------------------------------------------------------------------------
class Source:
    def __init__(self, take, frame, rule):
        self.take, self.frame, self.rule = take, frame, rule

    def pose(self, side):
        return self.take.pose(self.frame, side)

    def note(self):
        return {"take": os.path.basename(self.take.path), "frame": self.frame, "rule": self.rule}


def cut_sources(T):
    """the named still frames a gun's takes offer: hold, mag, pump, shell, drum, cover, bolt"""
    src = {}
    R = T.get("reload_full")
    if R is None:
        return src
    s2100 = R.segments("2100")
    if s2100:
        a, b = s2100[0]
        src["hold"] = Source(R, (a + b) // 2, "the middle of 2100: the two-handed hold after the reload")
    s2500 = R.segments("2500")
    if s2500:
        a, b = s2500[0]
        k, why = R.grasp_frame(a, b, "L_")
        if k is not None:
            src["mag"] = Source(R, k, "2500: " + why)
        k, why = R.peak_frame(a, b, "R_", 1.2)
        src["bolt"] = Source(R, k, "2500, right hand: " + why)
    s2513 = R.segments("2513")
    if s2513:
        a, b = s2513[0]
        k, why = R.grasp_frame(a, b, "L_")   # after the shell is let go, the grip that works the pump (the W870's is its hold)
        if k is None:
            k, why = R.peak_frame(a, b, "L_", 9.0)
        src["pump"] = Source(R, k, "2513: the hand closed on the pump / the cover; " + why)
    s2512 = R.segments("2512")
    if s2512:
        a, b = s2512[1] if len(s2512) > 1 else s2512[0]
        src["shell"] = Source(R, a, "2512, a cycle's first frame: a round in the hand")
        src["drum"] = Source(R, (a + b) // 2, "2512, mid-cycle: the hand holding the gun by the cylinder")
        src["cover"] = Source(R, a, "2512, a cycle's first frame, right hand: a round about to go in")
    return src


def plan_for(gun, src, donor):
    """(key suffix, left source, right source) for every spot this gun has; '' = the gun's own pose"""
    P = []
    hold, mag = src.get("hold"), src.get("mag")
    wrap, dshell = donor.get("pump"), donor.get("shell")
    if gun in PISTOL_MAG:
        P += [("", hold, None), (" @ handle", hold, None), (" @ magazine", mag, None),
              (" @ slide", wrap, None), (" @ slide from the left", wrap, None)]
    elif gun in LONG_MAG:
        P += [("", hold, None), (" @ magazine", mag, None), (" @ slide", wrap, None)]
        if gun == "ri3042":
            P += [(" @ right hand on the bolt", None, src.get("bolt"))]
    elif gun in PUMP:
        P += [("", hold, None), (" @ slide", src.get("pump"), None),
              (" @ rounds from the pouch", src.get("shell"), None), (" @ slide from the left", src.get("shell"), None)]
    elif gun in ROCKET:
        P += [("", hold, None), (" @ handle", hold, None), (" @ slide", src.get("pump"), None),
              (" @ rounds from the pouch", src.get("shell"), None), (" @ slide from the left", src.get("shell"), None)]
    elif gun in REVOLVER:
        P += [("", hold, None), (" @ handle", hold, None), (" @ drum", src.get("drum"), None),
              (" @ drum + right hand on the cover", src.get("drum"), src.get("cover")),
              (" @ right hand on the cover", None, src.get("cover")),
              (" @ rounds from the pouch", dshell, None)]
    elif gun in LAUNCHER:
        P += [("", hold, None), (" @ insert point", mag, None), (" @ rounds from the pouch", mag, None)]
    return [(k, l, r) for k, l, r in P if l is not None or r is not None]


# ---- the files ---------------------------------------------------------------------------------------------------------
def file_hash(p):
    return hashlib.md5(open(p, "rb").read()).hexdigest()


def classify(out_dir):
    """for every file in the guns folder: 'keep' (Tefa's own: unique, or the oldest of an identical set) or 'copy'"""
    files = sorted(glob.glob(os.path.join(out_dir, "*.json")))
    by_hash = {}
    for f in files:
        by_hash.setdefault(file_hash(f), []).append(f)
    nogun = os.path.join(out_dir, "no gun.json")
    nogun_hash = file_hash(nogun) if os.path.exists(nogun) else None
    verdict = {}
    for h, group in by_hash.items():
        if h == nogun_hash:
            for f in group:
                verdict[f] = "keep" if f == nogun else "copy"
            continue
        oldest = min(group, key=os.path.getmtime)
        for f in group:
            verdict[f] = "keep" if f == oldest else "copy"
    return verdict


def euler_deg(q):
    e = decompose(EULER, q)
    back = qangle(q, compose(EULER, e))
    if back > 0.01:
        raise SystemExit(f"euler_deg: {EULER} angles do not turn back into the take's rotation ({back:.4f} deg)")
    return [math.degrees(v) for v in e]


def main():
    global EULER
    ap = argparse.ArgumentParser()
    ap.add_argument("--takes", default=TAKES)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--app", default=APP)
    ap.add_argument("--archive", default=ARCHIVE)
    ap.add_argument("--gun", nargs="*")
    ap.add_argument("--fit", help="the euler probe's csv: print which Euler convention the engine uses, then stop")
    ap.add_argument("--euler", default=EULER, help="the multiplication order (from --fit)")
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    EULER = a.euler
    selftest()
    if a.fit:
        fit(a.fit)
        return
    stamp = datetime.date.today().isoformat()
    archive = os.path.join(a.archive, f"{stamp}-before-rest-poses")
    donor = cut_sources(load_takes(a.takes, WRAP_DONOR))
    verdict = classify(a.out) if os.path.isdir(a.out) else {}
    if not a.dry:
        os.makedirs(archive, exist_ok=True)
        for f in verdict:
            shutil.copy2(f, os.path.join(archive, os.path.basename(f)))
        print(f"archived {len(verdict)} existing pose file(s) to {archive}")
    guns = PISTOL_MAG + LONG_MAG + PUMP + ROCKET + REVOLVER + LAUNCHER
    written, kept, borrowed, written_names = 0, [], [], set()
    for gun in guns:
        if a.gun and gun not in a.gun:
            continue
        T = load_takes(a.takes, gun)
        if not T:
            print(f"{gun}: no take")
            continue
        src = cut_sources(T)
        for key, L, Rr in plan_for(gun, src, donor):
            name = f"{gun}_Inventory{key}.json"
            path = os.path.join(a.out, name)
            if verdict.get(path) == "keep":
                kept.append(name)
                continue
            joints = {}
            notes = {}
            if L is not None:
                joints.update({n: euler_deg(q) for n, q in L.pose("L_").items()})
                notes["left"] = L.note()
                if L.take is not T.get("reload_full") and L.take is not T.get("draw_idle"):
                    notes["left"]["borrowed_from"] = WRAP_DONOR
                    borrowed.append(name)
            if Rr is not None:
                joints.update({n: euler_deg(q) for n, q in Rr.pose("R_").items()})
                notes["right"] = Rr.note()
            doc = {"game": "re8", "character": "pl1000", "joints": joints,
                   "source": {"made_by": f"make_rest_poses.py {stamp}: the game's own finger pose, cut from the takes", **notes}}
            text = json.dumps(doc)
            curl = sum(curl_of(L.pose("L_")[f"L_{f}"]) for f in FINGERS[:CURL]) / CURL if L is not None else float("nan")
            what = f"{name}: {'replaced the copy' if path in verdict else 'new'}; left curl {curl:.0f} deg" if L is not None else f"{name}: right hand only"
            print(f"  {what}  <- {(L or Rr).rule}")
            if not a.dry:
                for d in (a.out, a.app):
                    if d and os.path.isdir(os.path.dirname(d.rstrip("\\/"))) or d == a.out:
                        os.makedirs(d, exist_ok=True)
                        with open(os.path.join(d, name), "w") as f:
                            f.write(text)
            written += 1
            written_names.add(name)
    # copies of other guns' poses that no spot of ours asks for (the "start N" placeholders): taken out, kept in the archive
    stale = [f for f, v in verdict.items() if v == "copy" and os.path.basename(f) not in written_names]
    for f in stale:
        if not a.dry:
            os.remove(f)
            app_twin = os.path.join(a.app, os.path.basename(f))
            if os.path.exists(app_twin):
                os.remove(app_twin)
        print(f"  {os.path.basename(f)}: a copy of another gun's pose with no game source: taken out (kept in the archive)")
    print(f"\n{written} pose file(s) {'would be ' if a.dry else ''}written; {len(kept)} of Tefa's own kept: {', '.join(kept) or '-'}")
    if borrowed:
        print(f"borrowed from the W870 (no game source of their own): {len(borrowed)}: {', '.join(borrowed)}")


if __name__ == "__main__":
    main()
