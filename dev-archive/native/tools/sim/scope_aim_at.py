"""aim_at.py <pitch_deg> <tag>: the rifle pose rotated about the eye (0, 1.70, 0) by pitch (negative = down), so the scope stays
at the eye while the head looks the same way; then a picture, the left eye saved full and small, and a zoom on the glass."""
import sys, os, math, time, subprocess
sys.path.insert(0, os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"))
import vb_input as I, vb_settings as S
from PIL import Image
pitch, tag = float(sys.argv[1]), sys.argv[2]
EYE = (0.0, 1.70, 0.0)
def rot(p):
    x, y, z = p[0] - EYE[0], p[1] - EYE[1], p[2] - EYE[2]
    a = math.radians(pitch)          # about the X axis; looking down = the point ahead moves down (-y) and nearer... (z toward 0)
    y2 = y * math.cos(a) - z * math.sin(a)
    z2 = y * math.sin(a) + z * math.cos(a)
    return (x + EYE[0], y2 + EYE[1], z2 + EYE[2])
R, L = (-0.07, 1.48, -0.10), (-0.07, 1.55, -0.45)
inp = I.Input().mode(poses="set", buttons="set")
inp.hand(S.HAND_RIGHT, grip=I.pose_from_ypr(rot(R), 0, 90 - pitch), aim=I.pose_from_ypr(rot(R), 0, 90 - pitch))
inp.hand(S.HAND_LEFT, grip=I.pose_from_ypr(rot(L), 0, 90 - pitch), aim=I.pose_from_ypr(rot(L), 0, 90 - pitch))
I.write(inp); print("hands rotated", pitch, "->", [round(v, 2) for v in rot(R)], [round(v, 2) for v in rot(L)], flush=True)
time.sleep(3.5)
T = os.environ["TEMP"]; M = os.path.expanduser("~/github-backups/visceral-re8-vr/dev-archive/native/tools/scope_measure.py")
out = os.path.join(T, f"{tag}.png"); print(subprocess.run([sys.executable, M, "shot", out], capture_output=True, text=True).stdout.strip())
im = Image.open(out); w, h = im.size
left = im.crop((0, 0, w // 2, h)); left.save(os.path.join(T, f"{tag}_left_full.png")); left.resize((w // 4, h // 2)).save(os.path.join(T, f"{tag}_left.png"))
print("saved", tag)
