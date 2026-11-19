"""door_touch.py [seconds] [from_z] [to_z] -- push both VR Bench hands slowly forward (room -Z) from from_z to to_z and hold,
kept alive with a small wobble (sleephands.cpp). For the doors-by-hand test (2026-11-19, b143): walk Ethan up to a shut
door (walk_to.py <name> 0.7), then run this; the log should say "a hand on a door: the game opens it"."""
import math, os, sys, time
sys.path.insert(0, os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"))
import vb_input as I, vb_settings as S
secs = float(sys.argv[1]) if len(sys.argv) > 1 else 4.0
z0 = float(sys.argv[2]) if len(sys.argv) > 2 else -0.15
z1 = float(sys.argv[3]) if len(sys.argv) > 3 else -0.75
t0 = time.time()
while time.time() - t0 < secs:
    t = time.time() - t0
    k = min(1.0, t / (secs * 0.6))
    z = z0 + (z1 - z0) * k
    w = 0.002 * math.sin(t * 40.0)
    inp = I.Input().mode(poses="set", buttons="set")
    rp = I.pose_from_ypr([0.22 + w, 1.35, z], 0, 0); inp.hand(S.HAND_RIGHT, grip=rp, aim=rp)
    lp = I.pose_from_ypr([-0.22 + w, 1.35, z], 0, 0); inp.hand(S.HAND_LEFT, grip=lp, aim=lp)
    I.write(inp)
    time.sleep(0.01)
print("hands pushed from z %.2f to %.2f over %.1f s" % (z0, z1, secs))
