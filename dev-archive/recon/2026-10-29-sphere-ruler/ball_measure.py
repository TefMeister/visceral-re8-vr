# ball_measure.py <png> : the calibration ball's pixel extent along the row and column through the screen centre.
# The ball is the only red-checkered thing near the centre: a pixel counts as "ball" when red clearly beats green and blue,
# or when it is the ball's flat dark grey next to such a pixel. Prints the extents; the maths is done by hand after.
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB"); W, H = im.size
px = im.load()
cx, cy = W // 2, H // 2
def is_red(p): r, g, b = p; return r > 60 and r > g * 1.6 and r > b * 1.6
def run(points):
    hits = [i for i, p in points if is_red(p)]
    return (min(hits), max(hits)) if hits else None
row = [(x, px[x, cy]) for x in range(W)]
col = [(y, px[cx, y]) for y in range(H)]
print("size", W, H, "centre", cx, cy)
print("red extent on the centre row:", run(row))
print("red extent on the centre column:", run(col))
# the widest red extent over all rows near the centre, for the full diameter
best = None
for y in range(0, H, 4):
    e = run([(x, px[x, y]) for x in range(W)])
    if e and (best is None or e[1] - e[0] > best[1] - best[0]): best = (e[0], e[1], y)
print("widest red row:", best)
