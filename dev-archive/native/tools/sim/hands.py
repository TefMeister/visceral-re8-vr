"""hands.py rx ry rz ryaw rpitch [lx ly lz lyaw lpitch] -- hold both controllers at fixed poses (room metres, degrees)."""
import sys, os
sys.path.insert(0, os.path.expanduser("~/.claude/plugins/cache/lanes-plugin/lanes/0.95.0/tools/vrbench"))
import vb_input as I, vb_settings as S
a = [float(v) for v in sys.argv[1:]]
inp = I.Input().mode(poses="set", buttons="set")
rp = I.pose_from_ypr(a[0:3], a[3], a[4]); inp.hand(S.HAND_RIGHT, grip=rp, aim=rp)
if len(a) >= 10:
    lp = I.pose_from_ypr(a[5:8], a[8], a[9]); inp.hand(S.HAND_LEFT, grip=lp, aim=lp)
I.write(inp); print("hands set")
