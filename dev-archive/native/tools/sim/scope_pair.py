"""pair.py <tag> [turn_seconds]: at the current place, the scope at the eye (picture A), the rifle lowered (picture B), the
glass compared with the world at the same spot; then, if asked, the player turned right with the stick for a new place."""
import sys, os, time, subprocess
sys.path.insert(0, os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"))
import vb_input as I, vb_settings as S
from PIL import Image
tag = sys.argv[1]; turn = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
T = os.environ["TEMP"]; M = os.path.expanduser("~/github-backups/visceral-re8-vr/dev-archive/native/tools/scope_measure.py")
LOG = os.path.join(T, "scope-pairs.tsv")
GLASS = (380, 610, 56)      # where the glass sits in the left eye with the level pose below (measured 2026-11-04)


def write(right, left, pitch, stick=None):
    inp = I.Input().mode(poses="set", buttons="set")
    kw = dict(grip=I.pose_from_ypr(right, 0, pitch), aim=I.pose_from_ypr(right, 0, pitch))
    if stick: kw["stick"] = stick
    inp.hand(S.HAND_RIGHT, **kw)
    inp.hand(S.HAND_LEFT, grip=I.pose_from_ypr(left, 0, pitch), aim=I.pose_from_ypr(left, 0, pitch))
    I.write(inp)


def shot(name):
    out = os.path.join(T, f"{name}.png")
    subprocess.run([sys.executable, M, "shot", out], capture_output=True, text=True)
    im = Image.open(out); w, h = im.size
    full = os.path.join(T, f"{name}_left_full.png"); im.crop((0, 0, w // 2, h)).save(full)
    return full


write((-0.07, 1.48, -0.10), (-0.07, 1.55, -0.45), 90); time.sleep(3.5)
a = shot(f"{tag}_scope")
write((0.25, 0.95, -0.15), (-0.25, 0.95, -0.15), -20); time.sleep(3.5)
b = shot(f"{tag}_world")
r = subprocess.run([sys.executable, M, "compare2", a, b, *map(str, GLASS), "--label", tag, "--log", LOG], capture_output=True, text=True)
print(r.stdout.strip(), flush=True)
sa, sb = Image.open(a), Image.open(b)
sheet = Image.new("RGB", (960, 480)); sheet.paste(sa.crop((140, 370, 620, 850)), (0, 0)); sheet.paste(sb.crop((140, 370, 620, 850)), (480, 0))
sheet.save(os.path.join(T, f"{tag}_pair.png"))
if turn > 0:
    write((0.25, 0.95, -0.15), (-0.25, 0.95, -0.15), -20, stick=(1.0, 0.0)); time.sleep(turn)
    write((0.25, 0.95, -0.15), (-0.25, 0.95, -0.15), -20); time.sleep(1.0)
    print(f"turned right {turn} s", flush=True)
