"""hand_swing.py [seconds] [amp_m] [hz] -- swing the LEFT controller smoothly side to side (VR Bench), the right one still
with a gun's pose. For the free-hand jitter probe (smooth.cpp, 2026-11-10): a smooth controller must give a smooth hand."""
import sys, os, time, math
sys.path.insert(0, os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"))
import vb_input as I, vb_settings as S
secs = float(sys.argv[1]) if len(sys.argv) > 1 else 10.0
amp = float(sys.argv[2]) if len(sys.argv) > 2 else 0.25
hz = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
RIGHT = [0.15, 1.35, -0.30, 0, 35]
t0 = time.perf_counter()
while True:
    t = time.perf_counter() - t0
    if t > secs: break
    x = -0.35 + amp * math.sin(2 * math.pi * hz * t)
    y = 1.15 + 0.5 * amp * math.sin(2 * math.pi * hz * t * 0.5)
    inp = I.Input().mode(poses="set", buttons="set")
    r = I.pose_from_ypr(RIGHT[0:3], RIGHT[3], RIGHT[4]); inp.hand(S.HAND_RIGHT, grip=r, aim=r)
    l = I.pose_from_ypr([x, y, -0.35], 0, 0); inp.hand(S.HAND_LEFT, grip=l, aim=l)
    I.write(inp)
    time.sleep(0.004)
print("swing done")
