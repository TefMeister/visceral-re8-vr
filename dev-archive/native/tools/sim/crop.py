"""crop.py <in.png> <out.png> x0 y0 x1 y1 [scale] - cut a part of a picture and enlarge it."""
import sys
from PIL import Image
a = sys.argv
x0, y0, x1, y1 = (int(v) for v in a[3:7])
k = float(a[7]) if len(a) > 7 else 2.5
im = Image.open(a[1]).crop((x0, y0, x1, y1))
im.resize((int(im.width * k), int(im.height * k))).save(a[2])
