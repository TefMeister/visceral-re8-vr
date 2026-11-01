"""vb.py press <hand> <button> [sec]  |  vb.py pass   -- VR Bench buttons; poses passed through from the simulator."""
import sys, time, os
sys.path.insert(0, os.path.expanduser("~/.claude/plugins/cache/lanes-plugin/lanes/0.95.0/tools/vrbench"))
import vb_input as I, vb_settings as S
H = {"left": S.HAND_LEFT, "right": S.HAND_RIGHT}
def put(hand=None, **kw):
    inp = I.Input().mode(poses="pass", buttons="set")
    if hand is not None: inp.hand(H[hand], **kw)
    I.write(inp)
cmd = sys.argv[1]
if cmd == "press":
    hand, btn = sys.argv[2], sys.argv[3]; sec = float(sys.argv[4]) if len(sys.argv) > 4 else 0.3
    val = 1.0 if btn in ("trigger", "squeeze") else True
    put(hand, **{btn: val}); time.sleep(sec); put(); print("pressed", hand, btn, sec)
else:
    put(); print("released all")
