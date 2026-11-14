"""hand_follow.py -- how well the drawn LEFT hand follows its controller, free and holding a spare magazine (2026-11-14).

Tefa, in the headset: "my left hand when holding the spare mag when a mag is still in the gun, left hand moves very weird and
sluggishly. can you look at it yourself in the pretend headset?". After drive.sh with the LEMI in hand (keys.py <pid> 2):
the left controller swings smoothly side to side (VR Bench), first empty, then with a spare from the pouch (LG held, the gun's
magazine still seated); a recorder in the game (zz_visceral_eval.lua's E table) logs every frame: the L_Hand joint in the
world, the left controller in the room. Printed per phase: how far the hand moves for the controller's 1 m (should be ~1), how
late it follows (ms, by cross-correlation), and how much of the hand's motion is NOT the controller's (the "weird" part).
    python hand_follow.py            both phases
    python hand_follow.py free       only the empty hand"""
import json, math, os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"))
import vb_input as I, vb_settings as S

G = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
LOG = os.path.join(G, "re2_framework_log.txt")
RIGHT = [0.15, 1.35, -0.30, 0, 35]
POUCH = [-0.20, 1.08, -0.02, 0, 0]
CENTRE = [-0.30, 1.15, -0.30]
AMP, HZ, SECS = 0.15, 0.8, 5.0
REC = '''
E.rec_on = false
E.rec = {}
if not E.rec_hooked2 then
    E.rec_hooked2 = true   -- (2: with the hand's turn; a recorder hooked once stays in the game)
    re.on_frame(function()
        if not E.rec_on then return end
        pcall(function()
            local j = re8vr.player:call('get_Transform'):call('getJointByName', 'L_Hand')
            local p = j:call('get_Position')
            local q = j:call('get_Rotation')
            local c = vrmod:get_controllers()
            local cp = vrmod:get_transform(c[1])[3]
            E.rec[#E.rec + 1] = { os.clock(), p.x, p.y, p.z, cp.x, cp.y, cp.z, q.w, q.x, q.y, q.z }
        end)
    end)
end
return 'recorder ready'
'''


def rv(code):
    return subprocess.run([sys.executable, os.path.join(HERE, "rv.py"), "--front", code], capture_output=True, text=True).stdout.strip()


def put(left, squeeze, ryaw=0.0):
    inp = I.Input().mode(poses="set", buttons="set")
    r = I.pose_from_ypr(RIGHT[0:3], RIGHT[3] + ryaw, RIGHT[4]); inp.hand(S.HAND_RIGHT, grip=r, aim=r)
    l = I.pose_from_ypr(left[0:3], 0, 0); inp.hand(S.HAND_LEFT, grip=l, aim=l, squeeze=squeeze)
    I.write(inp)


def swing(squeeze):
    t0 = time.perf_counter()
    while True:
        t = time.perf_counter() - t0
        if t > SECS: break
        s = math.sin(2 * math.pi * HZ * t)
        put([CENTRE[0] + AMP * s, CENTRE[1] + 0.4 * AMP * s, CENTRE[2]], squeeze)
        time.sleep(0.004)


def turn_gun(squeeze):   # the left controller still; only the gun hand turns side to side (25 degrees)
    t0 = time.perf_counter()
    while True:
        t = time.perf_counter() - t0
        if t > SECS: break
        put(CENTRE, squeeze, 25.0 * math.sin(2 * math.pi * HZ * t))
        time.sleep(0.004)


def left_turn(rows):   # how far the left hand turns over the run: the largest angle from its first turn (degrees)
    q0 = rows[0][7:11]; worst = 0.0
    for r in rows:
        d = abs(sum(a * b for a, b in zip(q0, r[7:11])))
        worst = max(worst, math.degrees(2 * math.acos(min(1.0, d))))
    return worst


def record(squeeze, name, motion=None):
    put(CENTRE, squeeze); time.sleep(1.0)
    rv("E.rec = {}; E.rec_on = true; return 'on'")
    (motion or swing)(squeeze)
    rv("E.rec_on = false; json.dump_file('visceral_re8/hand_follow_%s.json', E.rec); return #E.rec" % name)
    put(CENTRE, squeeze)
    with open(os.path.join(G, "reframework", "data", "visceral_re8", "hand_follow_%s.json" % name)) as f:
        return json.load(f)


def analyse(rows, name):
    if len(rows) < 30: print("%s: only %d frames recorded" % (name, len(rows))); return
    t = [r[0] for r in rows]
    h = [r[1:4] for r in rows]; c = [r[4:7] for r in rows]
    def mean(v): return [sum(x[i] for x in v) / len(v) for i in range(3)]
    def axis(v):   # the main direction of a motion (power iteration on the scatter)
        m = mean(v); d = [[x[i] - m[i] for i in range(3)] for x in v]
        a = [1.0, 0.3, 0.2]
        for _ in range(30):
            b = [sum(r[i] * sum(r[k] * a[k] for k in range(3)) for r in d) for i in range(3)]
            n = math.sqrt(sum(x * x for x in b)) or 1.0; a = [x / n for x in b]
        return m, a, d
    hm, ha, hd = axis(h); cm, ca, cd = axis(c)
    hp = [sum(x[i] * ha[i] for i in range(3)) for x in hd]
    cp = [sum(x[i] * ca[i] for i in range(3)) for x in cd]
    def amp(v): return (max(v) - min(v)) / 2
    gain = amp(hp) / (amp(cp) or 1e-9)
    # lag: the frame shift with the best correlation (the hand's sign made to match)
    best, best_k = -2.0, 0
    for k in range(0, 40):
        a = cp[:len(cp) - k] if k else cp; b = hp[k:]
        n = min(len(a), len(b))
        if n < 20: break
        ma, mb = sum(a[:n]) / n, sum(b[:n]) / n
        num = sum((a[i] - ma) * (b[i] - mb) for i in range(n))
        den = math.sqrt(sum((a[i] - ma) ** 2 for i in range(n)) * sum((b[i] - mb) ** 2 for i in range(n))) or 1e-9
        r = abs(num / den)
        if r > best: best, best_k = r, k
    dt = (t[-1] - t[0]) / max(1, len(t) - 1)
    # the part of the hand's motion off its main line (the "weird" wobble), in cm
    off = [math.sqrt(max(0.0, sum(x[i] * x[i] for i in range(3)) - p * p)) for x, p in zip(hd, hp)]
    print("%-6s %4d frames | hand moves %.2f x the controller | follows %.0f ms late (match %.2f) | off its line %.1f cm (avg)"
          % (name, len(rows), gain, best_k * dt * 1000, best, 100 * sum(off) / len(off)))


def main(mode):
    print(rv(REC))
    if mode == "turn":   # 2026-11-14: only the gun hand turns; a free left hand should not turn with it
        a = record(0.0, "turnfree", turn_gun)
        print("free   %d frames | the left hand turned up to %.1f deg while only the gun turned 25" % (len(a), left_turn(a)))
        put(POUCH, 0.0); time.sleep(0.8); put(POUCH, 1.0); time.sleep(1.5)
        b = record(1.0, "turnspare", turn_gun)
        print("spare  %d frames | the left hand turned up to %.1f deg while only the gun turned 25" % (len(b), left_turn(b)))
        put(CENTRE, 0.0); time.sleep(1.0)
        return
    put(CENTRE, 0.0); time.sleep(1.0)
    free = record(0.0, "free")
    analyse(free, "free")
    if mode == "free": return
    put(POUCH, 0.0); time.sleep(0.8); put(POUCH, 1.0); time.sleep(1.5)
    with open(LOG, "rb") as f: f.seek(max(0, os.path.getsize(LOG) - 60000)); tail = f.read().decode("utf-8", "replace")
    print("spare taken:", "a spare magazine in the left hand" in tail)
    spare = record(1.0, "spare")
    analyse(spare, "spare")
    put(CENTRE, 0.0); time.sleep(1.0)   # LG let go: the spare back in the pouch


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "both")
