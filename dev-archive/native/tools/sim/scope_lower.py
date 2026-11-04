"""lower.py <tag>: the rifle lowered out of view (hands down by the hips, pointing down), a picture, the left eye saved."""
import sys, os, time, subprocess
sys.path.insert(0, os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"))
import vb_input as I, vb_settings as S
from PIL import Image
tag = sys.argv[1]
inp = I.Input().mode(poses="set", buttons="set")
inp.hand(S.HAND_RIGHT, grip=I.pose_from_ypr((0.25, 0.95, -0.15), 0, -20), aim=I.pose_from_ypr((0.25, 0.95, -0.15), 0, -20))
inp.hand(S.HAND_LEFT, grip=I.pose_from_ypr((-0.25, 0.95, -0.15), 0, -20), aim=I.pose_from_ypr((-0.25, 0.95, -0.15), 0, -20))
I.write(inp); time.sleep(3.5)
T = os.environ["TEMP"]; M = os.path.expanduser("~/github-backups/visceral-re8-vr/dev-archive/native/tools/scope_measure.py")
out = os.path.join(T, f"{tag}.png"); print(subprocess.run([sys.executable, M, "shot", out], capture_output=True, text=True).stdout.strip())
im = Image.open(out); w, h = im.size
left = im.crop((0, 0, w // 2, h)); left.save(os.path.join(T, f"{tag}_left_full.png")); left.resize((w // 4, h // 2)).save(os.path.join(T, f"{tag}_left.png"))
print("saved", tag)
