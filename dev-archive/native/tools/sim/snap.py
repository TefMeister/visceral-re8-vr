"""snap.py <out.png> <label> -- a close picture (the middle of the window) with the left hand's spot number and a label drawn in."""
import json, os, subprocess, sys
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
subprocess.run([sys.executable, os.path.join(HERE, "shot.py"), sys.argv[1], "1.0"], capture_output=True)
try: d = json.load(open(r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE\reframework\data\visceral_re8\zones_state.json"))
except Exception: d = {}
try: hp = json.load(open(r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE\reframework\data\hand_poser\state.json")).get("spot", "?")
except Exception: hp = "?"
im = Image.open(sys.argv[1]).convert("RGB"); w, h = im.size
c = [float(v) for v in os.environ.get("SNAP_BOX", "0.17 0.06 0.94 0.97").split()]
im = im.crop((int(w * c[0]), int(h * c[1]), int(w * c[2]), int(h * c[3])))
t = "%s | spot %s | pose '%s'" % (sys.argv[2], d.get("spot"), hp)
ImageDraw.Draw(im).rectangle((0, 0, im.size[0], 14), fill=(0, 0, 0)); ImageDraw.Draw(im).text((4, 2), t, fill=(255, 255, 0))
im.save(sys.argv[1]); print(t)
