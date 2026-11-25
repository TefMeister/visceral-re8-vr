"""bgdiff.py <out.png> <a.png> <b.png> [...] [--crop x0,y0,x1,y1] - how much each picture differs from the one before,
and a strip of them (cropped) side by side / stacked for a look."""
import sys
from PIL import Image, ImageChops, ImageStat

args = [a for a in sys.argv[1:] if not a.startswith("--crop")]
crop = next((tuple(int(v) for v in a.split("=", 1)[1].split(",")) for a in sys.argv[1:] if a.startswith("--crop=")), None)
out, names = args[0], args[1:]
ims = [Image.open(n).convert("RGB") for n in names]
for i in range(1, len(ims)):
    print("change %d: %.2f" % (i, sum(ImageStat.Stat(ImageChops.difference(ims[i - 1], ims[i])).mean) / 3))
parts = [im.crop(crop) if crop else im for im in ims]
wd = 1600; parts = [p.resize((wd, max(1, int(wd * p.height / p.width)))) for p in parts]
o = Image.new("RGB", (wd, sum(p.height for p in parts))); y = 0
for p in parts:
    o.paste(p, (0, y)); y += p.height
o.save(out)
