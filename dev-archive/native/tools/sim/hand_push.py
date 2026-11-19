"""hand_push.py <head_yaw_deg> [seconds] [from_m] [to_m] [pitch_deg] -- push both VR Bench hands forward ALONG THE VIEW
(the simulator head's yaw; controllers are in room space, not head space: door_touch.py's plain -Z only suits yaw 0 / a
door met by luck), from from_m to to_m in front of the head, then hold; kept alive with a 2 mm wobble. pitch tilts the
controllers (fingers up / down). For the wall tests (q_hand_wall.lua reads the result). 2026-11-19."""
import math, os, sys, time
sys.path.insert(0, os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"))
import vb_input as I, vb_settings as S
yaw = float(sys.argv[1]); secs = float(sys.argv[2]) if len(sys.argv) > 2 else 6.0
d0 = float(sys.argv[3]) if len(sys.argv) > 3 else 0.2; d1 = float(sys.argv[4]) if len(sys.argv) > 4 else 0.9
pitch = float(sys.argv[5]) if len(sys.argv) > 5 else 0.0
y = math.radians(yaw); fwd = (-math.sin(y), -math.cos(y)); right = (math.cos(y), -math.sin(y))
t0 = time.time()
while time.time() - t0 < secs:
    t = time.time() - t0
    d = d0 + (d1 - d0) * min(1.0, t / (secs * 0.5)); w = 0.002 * math.sin(t * 40.0)
    inp = I.Input().mode(poses="set", buttons="set")
    for hand, side in ((S.HAND_RIGHT, 0.22), (S.HAND_LEFT, -0.22)):
        p = I.pose_from_ypr([fwd[0] * d + right[0] * side + w, 1.35, fwd[1] * d + right[1] * side], yaw, pitch)
        inp.hand(hand, grip=p, aim=p)
    I.write(inp); time.sleep(0.01)
print("hands pushed %.2f -> %.2f m along yaw %.0f" % (d0, d1, yaw))
