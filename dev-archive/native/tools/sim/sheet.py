"""sheet.py <out.png> <cols> <in1.png> ... -- tile pictures into one sheet"""
import sys
from PIL import Image
ims = [Image.open(f) for f in sys.argv[3:]]; cols = int(sys.argv[2]); w, h = ims[0].size
s = Image.new("RGB", (w * cols, h * ((len(ims) + cols - 1) // cols)))
for i, im in enumerate(ims): s.paste(im, (w * (i % cols), h * (i // cols)))
s.save(sys.argv[1])
