# ball_fit.py <png> : fit a circle to the test ball's upper-left outline (flat grey or dark-red pixels) and print its radius in px.
import sys, math
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB"); W, H = im.size; px = im.load()
def ball(p):
    r, g, b = p
    flat_grey = abs(r - g) < 12 and abs(g - b) < 12 and 28 <= r <= 70
    dark_red = r > 55 and r < 120 and g < 45 and b < 45 and r > g * 1.7
    return flat_grey or dark_red
pts = []
for x in range(700, 1900, 10):            # the top edge: first ball pixel from above, needs 12 ball pixels in a row below it
    for y in range(400, H - 80):
        if all(ball(px[x, yy]) for yy in range(y, min(y + 12, H - 80))):
            pts.append((x, y)); break
for y in range(600, 1340, 10):            # the left edge: first ball pixel from the left
    for x in range(600, 1500):
        if all(ball(px[xx, y]) for xx in range(x, x + 12)):
            pts.append((x, y)); break
# least-squares circle (Kasa), then throw out points over 25 px off and fit again
def fit(P):
    n = len(P); sx = sum(p[0] for p in P); sy = sum(p[1] for p in P)
    sxx = sum(p[0]**2 for p in P); syy = sum(p[1]**2 for p in P); sxy = sum(p[0]*p[1] for p in P)
    sxxx = sum(p[0]**3 for p in P); syyy = sum(p[1]**3 for p in P); sxyy = sum(p[0]*p[1]**2 for p in P); sxxy = sum(p[0]**2*p[1] for p in P)
    A = [[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, n]]; B = [-(sxxx + sxyy), -(sxxy + syyy), -(sxx + syy)]
    import numpy as np
    a, b, c = np.linalg.solve(np.array(A), np.array(B))
    cx, cy = -a / 2, -b / 2; r = math.sqrt(cx**2 + cy**2 - c); return cx, cy, r
cx, cy, r = fit(pts)
keep = [p for p in pts if abs(math.hypot(p[0]-cx, p[1]-cy) - r) < 25]
cx, cy, r = fit(keep)
print(f"points {len(pts)} kept {len(keep)}: centre ({cx:.0f}, {cy:.0f}) radius {r:.0f} px")
