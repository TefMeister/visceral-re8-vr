"""flick.py <up|down|left|right> [times] -- one-row menu steps: the left stick pushed for 30 ms (a 0.1 s push moved two rows
on Village's main menu, 2026-11-23), 0.6 s apart. Poses are passed through."""
import sys, os, time
sys.path.insert(0, os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"))
import vb_input as I, vb_settings as S
d = {"up": (0, 1), "down": (0, -1), "left": (-1, 0), "right": (1, 0)}[sys.argv[1]]
def st(x, y):
    inp = I.Input().mode(poses="pass", buttons="set"); inp.hand(S.HAND_LEFT, stick=(float(x), float(y))); I.write(inp)
for _ in range(int(sys.argv[2]) if len(sys.argv) > 2 else 1):
    st(*d); time.sleep(0.03); st(0, 0); time.sleep(0.6)
