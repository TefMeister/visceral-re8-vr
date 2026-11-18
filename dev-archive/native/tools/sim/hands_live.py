"""hands_live.py <seconds> rx ry rz ryaw rpitch [lx ly lz lyaw lpitch] -- like hands.py, but keeps the controllers alive for
<seconds>: rewritten every 10 ms with a 2 mm wobble, so Visceral RE8's sleeping-controller rule (sleephands.cpp: 20 frames
without one changed number = asleep, the hand goes down to the hip) never fires during a test (2026-11-18: hands.py's
still pose let it fire and the wall test read the hip instead of the hand). HL_RGRIP=1 holds the right grip too (RE2 / RE3 raise
the gun only while it is held)."""
import math, os, sys, time
sys.path.insert(0, os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"))
import vb_input as I, vb_settings as S

secs = float(sys.argv[1])
a = [float(v) for v in sys.argv[2:]]
t0 = time.time()
while time.time() - t0 < secs:
    w = 0.002 * math.sin((time.time() - t0) * 40.0)
    inp = I.Input().mode(poses="set", buttons="set")
    rp = I.pose_from_ypr([a[0] + w, a[1], a[2]], a[3], a[4]); inp.hand(S.HAND_RIGHT, grip=rp, aim=rp, squeeze=1.0 if os.environ.get("HL_RGRIP") == "1" else None)
    if len(a) >= 10:
        lp = I.pose_from_ypr([a[5] + w, a[6], a[7]], a[8], a[9]); inp.hand(S.HAND_LEFT, grip=lp, aim=lp)
    I.write(inp)
    time.sleep(0.01)
print("hands held alive for %.1f s" % secs)
