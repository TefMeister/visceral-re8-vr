"""regiondiff.py x0 y0 x1 y1 a.png b.png [c.png d.png ...] - pairs (a,b), (c,d)...: how many pixels in the box changed by more
than 20 (of 255) and the largest change: tells a frozen thing from a moving one between two pictures."""
import sys
from PIL import Image, ImageChops
x0, y0, x1, y1 = (int(v) for v in sys.argv[1:5])
files = sys.argv[5:]
for i in range(0, len(files) - 1, 2):
    a = Image.open(files[i]).convert('RGB').crop((x0, y0, x1, y1))
    b = Image.open(files[i + 1]).convert('RGB').crop((x0, y0, x1, y1))
    d = list(ImageChops.difference(a, b).convert('L').getdata())
    print('%s vs %s: %d pixels changed >20, max %d' % (files[i].split('/')[-1], files[i + 1].split('/')[-1], sum(1 for v in d if v > 20), max(d)))
