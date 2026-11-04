"""walkshot.py <tag> <walk_seconds> [turn_seconds]: level rifle pose at the eye; walk forward (left stick) and/or turn (right
stick) first; then a picture, the left eye saved full + small, and the ring measurement at the known glass spot."""
import sys, os, time, subprocess
sys.path.insert(0, os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"))
import vb_input as I, vb_settings as S
from PIL import Image
tag, walk = sys.argv[1], float(sys.argv[2]); turn = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
T = os.environ["TEMP"]; M = os.path.expanduser("~/github-backups/visceral-re8-vr/dev-archive/native/tools/scope_measure.py")
R, L = (-0.07, 1.48, -0.10), (-0.07, 1.55, -0.45)
def write(lstick=None, rstick=None):
    inp = I.Input().mode(poses="set", buttons="set")
    rk = dict(grip=I.pose_from_ypr(R, 0, 90), aim=I.pose_from_ypr(R, 0, 90)); lk = dict(grip=I.pose_from_ypr(L, 0, 90), aim=I.pose_from_ypr(L, 0, 90))
    if rstick: rk["stick"] = rstick
    if lstick: lk["stick"] = lstick
    inp.hand(S.HAND_RIGHT, **rk); inp.hand(S.HAND_LEFT, **lk); I.write(inp)
if turn: write(rstick=(1.0, 0.0)); time.sleep(turn); write(); time.sleep(0.5)
if walk: write(lstick=(0.0, 1.0)); time.sleep(walk); write(); time.sleep(0.5)
write(); time.sleep(3.0)
out = os.path.join(T, f"{tag}.png"); subprocess.run([sys.executable, M, "shot", out], capture_output=True, text=True)
im = Image.open(out); w, h = im.size
left = im.crop((0, 0, w // 2, h)); left.save(os.path.join(T, f"{tag}_left_full.png")); left.resize((480, 516)).save(os.path.join(T, f"{tag}_small.png"))
print(subprocess.run([sys.executable, M, "compare", os.path.join(T, f"{tag}_left_full.png"), "380", "610", "56", "--label", tag,
                      "--log", os.path.join(T, "scope-walls.tsv"), "--sector", "100", "260"], capture_output=True, text=True).stdout.strip())
