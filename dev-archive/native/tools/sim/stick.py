import sys, os, time
sys.path.insert(0, os.path.expanduser("~/.claude/plugins/cache/lanes-plugin/lanes/0.95.0/tools/vrbench"))
import vb_input as I, vb_settings as S
h = S.HAND_LEFT if sys.argv[1] == "left" else S.HAND_RIGHT
inp = I.Input().mode(poses="pass", buttons="set"); inp.hand(h, stick=(float(sys.argv[2]), float(sys.argv[3]))); I.write(inp); time.sleep(0.4)
I.write(I.Input().mode(poses="pass", buttons="set")); print("stick", sys.argv[1:])
