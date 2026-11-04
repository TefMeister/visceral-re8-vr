"""scope_measure.py - the scope picture against the world behind it, measured, not judged by eye (2026-11-04, Fable).

Tefa (2026-10-31): "if all the adaptive adjustments are off, how can the scope and game picture still differ? and is
there any chance at all ... using all the tools and knowledge we have, somehow match them up?"

    python scope_measure.py shot <out.png> [--eye left]        ask the OpenXR Simulator for a full-size picture
    python scope_measure.py find <png>                          find the scope glass (the dark vignette ring) in it
    python scope_measure.py compare <png> <cx> <cy> <r> [--label <spot>] [--log <tsv>]
                                                                mean colour INSIDE the glass (r < 0.6 R, reticle masked)
                                                                against the world in a ring just OUTSIDE it
                                                                (1.25 R .. 1.7 R); the per-channel ratio is what the
                                                                scope's trim must undo
    python scope_measure.py fit <tsv>                           across spots: is the gap one gain (fix: trim), or does
                                                                it change with brightness (fix: the curve)?

The glass shows the aim point magnified; on a flat, evenly lit surface (a wall, snow, the sky) the pixels inside and
just outside the ring are the same material, so any difference is the recipe's. Runs on the home PC beside the
simulator (%LOCALAPPDATA%/OpenXR-Simulator/screenshot_request.json -> screenshot.png). Only the game runs here.
"""
import json
import math
import os
import sys
import time

SIM_DIR = os.path.join(os.environ.get("LOCALAPPDATA", ""), "OpenXR-Simulator")
REQUEST = os.path.join(SIM_DIR, "screenshot_request.json")
OUTPUTS = [os.path.join(SIM_DIR, n) for n in ("screenshot.png", "screenshot.bmp", "screenshot.jpg", "screenshot.jpeg")]
INNER = 0.6          # the measured disc, as a share of the glass radius (inside the vignette)
RING_IN, RING_OUT = 1.25, 1.7
RETICLE_DARK = 0.55  # a pixel this much darker than the disc's median is reticle / ring, not picture


def shot(out, eye="left"):
    os.makedirs(SIM_DIR, exist_ok=True)
    for p in OUTPUTS:
        try:
            os.remove(p)
        except OSError:
            pass
    t0 = time.time()
    with open(REQUEST, "w") as f:
        json.dump({"timestamp": t0, "eye": eye, "include_ui": False, "requested_by": "scope_measure"}, f)
    while time.time() - t0 < 8:
        for p in OUTPUTS:
            if os.path.exists(p) and os.path.getmtime(p) >= t0 - 0.5:
                time.sleep(0.2)
                from PIL import Image
                im = Image.open(p).convert("RGB")
                im.save(out)
                try:
                    os.remove(p)
                    os.remove(REQUEST)
                except OSError:
                    pass
                print(f"shot: {out} {im.size[0]}x{im.size[1]}")
                return 0
        time.sleep(0.1)
    print("no picture came within 8 s (is the simulator running a game?)")
    return 1


def load_rgb(png):
    from PIL import Image
    import numpy as np
    return np.asarray(Image.open(png).convert("RGB")).astype("float32") / 255.0


def find(png):
    """the glass: the darkest ring-shaped structure. A coarse search over centres and radii on a downscaled, blurred
    luminance: score = mean lum on the ring (dark) minus mean lum just inside and just outside (brighter)."""
    import numpy as np
    from PIL import Image, ImageFilter
    im = Image.open(png).convert("L")
    W, H = im.size
    scale = 4
    small = im.resize((W // scale, H // scale)).filter(ImageFilter.GaussianBlur(1.5))
    a = np.asarray(small).astype("float32") / 255.0
    h, w = a.shape
    best = None
    ys, xs = np.mgrid[0:h, 0:w]
    for r in range(max(8, h // 12), h // 2, 3):
        for cy in range(r, h - r, 4):
            for cx in range(r, w - r, 4):
                d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2)
                ring = a[(d > r * 0.93) & (d < r * 1.03)]
                inside = a[(d > r * 0.75) & (d < r * 0.88)]
                outside = a[(d > r * 1.08) & (d < r * 1.2)]
                if len(ring) < 20 or len(inside) < 20 or len(outside) < 20:
                    continue
                score = (inside.mean() + outside.mean()) / 2 - ring.mean()
                if best is None or score > best[0]:
                    best = (score, cx * scale, cy * scale, r * scale)
    if best is None:
        print("no ring found")
        return 1
    print(f"glass: cx={best[1]} cy={best[2]} r={best[3]} (score {best[0]:.3f}); check it on the picture")
    return 0


def compare(png, cx, cy, r, label="", log=None, sector=None):
    """sector = (a0, a1) in degrees (0 = right, 90 = up, counter-clockwise): only that part of the outside ring is the
    world sample, so the scope's own tube (which runs from the glass to the lower right in a right-handed hold) is
    never counted as 'world'. Default: the upper-left half, 100..260."""
    import numpy as np
    a = load_rgb(png)
    H, W, _ = a.shape
    ys, xs = np.mgrid[0:H, 0:W]
    d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2)
    lum = a @ np.array([0.2126, 0.7152, 0.0722], dtype="float32")
    disc = d < r * INNER
    med = np.median(lum[disc])
    disc_clean = disc & (lum > med * RETICLE_DARK)
    ring = (d > r * RING_IN) & (d < r * RING_OUT)
    a0, a1 = sector or (100.0, 260.0)
    ang = (np.degrees(np.arctan2(-(ys - cy), xs - cx)) + 360.0) % 360.0
    ring = ring & (ang >= a0) & (ang <= a1)
    ins = a[disc_clean].mean(axis=0)
    out = a[ring].mean(axis=0)
    ratio = out / np.maximum(ins, 1e-4)
    lin_in = srgb_to_linear(ins)
    lin_out = srgb_to_linear(out)
    lin_ratio = lin_out / np.maximum(lin_in, 1e-5)
    print(f"{label or os.path.basename(png)}: inside RGB {ins.round(3)}  outside RGB {out.round(3)}")
    print(f"  world / scope, as shown: R {ratio[0]:.3f} G {ratio[1]:.3f} B {ratio[2]:.3f}   (1.0 = the same)")
    print(f"  world / scope, in light:  R {lin_ratio[0]:.3f} G {lin_ratio[1]:.3f} B {lin_ratio[2]:.3f}   "
          f"brightness {lin_out.mean() / max(lin_in.mean(), 1e-5):.3f}; colour of the gap (B/R) {lin_ratio[2] / lin_ratio[0]:.3f}")
    print(f"  disc pixels {int(disc_clean.sum())} of {int(disc.sum())}, ring pixels {int(ring.sum())}; "
          f"outside lum {lum[ring].mean():.3f} (dark 0 .. 1 bright)")
    if log:
        new = not os.path.exists(log)
        with open(log, "a", encoding="utf-8") as f:
            if new:
                f.write("label\tlum_out\tin_r\tin_g\tin_b\tout_r\tout_g\tout_b\tlin_ratio_r\tlin_ratio_g\tlin_ratio_b\n")
            f.write("\t".join([label or os.path.basename(png), f"{lum[ring].mean():.4f}"] +
                              [f"{v:.4f}" for v in list(ins) + list(out) + list(lin_ratio)]) + "\n")
    return 0


def compare2(with_png, without_png, cx, cy, r, zoom=4.0, label="", log=None, search=24):
    """the glass (scope at the eye) against the WORLD's own rendering of the same spot: a second picture with the rifle
    lowered, same head. The glass shows a region zoom x smaller than it looks, so the world sample is a disc of
    radius INNER * r / zoom around the glass centre; the centre is searched within +-search px for the best match of
    the glass's texture (the bore is only roughly on the eye line). Means in sRGB and linear light, the ratio logged."""
    import numpy as np
    from PIL import Image
    a = load_rgb(with_png)
    b = load_rgb(without_png)
    H, W, _ = a.shape
    ys, xs = np.mgrid[0:H, 0:W]
    d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2)
    lum_a = a @ np.array([0.2126, 0.7152, 0.0722], dtype="float32")
    disc = d < r * INNER
    med = np.median(lum_a[disc])
    disc_clean = disc & (lum_a > med * RETICLE_DARK)
    ins = a[disc_clean].mean(axis=0)
    # the glass's texture shrunk by the zoom, matched against the world picture near the centre
    side = int(r * INNER)
    glass = Image.fromarray((a[int(cy - side):int(cy + side), int(cx - side):int(cx + side)] * 255).astype("uint8"))
    small = np.asarray(glass.resize((max(4, int(2 * side / zoom)), max(4, int(2 * side / zoom))))).astype("float32") / 255.0
    sl = small @ np.array([0.2126, 0.7152, 0.0722], dtype="float32")
    sl = (sl - sl.mean()) / (sl.std() + 1e-6)
    hs = sl.shape[0] // 2
    lum_b = b @ np.array([0.2126, 0.7152, 0.0722], dtype="float32")
    best, bx, by = -2.0, int(cx), int(cy)
    for oy in range(-search, search + 1, 2):
        for ox in range(-search, search + 1, 2):
            px, py = int(cx) + ox, int(cy) + oy
            patch = lum_b[py - hs:py - hs + sl.shape[0], px - hs:px - hs + sl.shape[1]]
            if patch.shape != sl.shape:
                continue
            p = (patch - patch.mean()) / (patch.std() + 1e-6)
            score = float((p * sl).mean())
            if score > best:
                best, bx, by = score, px, py
    rw = max(2.0, r * INNER / zoom)
    d2 = np.sqrt((xs - bx) ** 2 + (ys - by) ** 2)
    out = b[d2 < rw].mean(axis=0)
    lin_in, lin_out = srgb_to_linear(ins), srgb_to_linear(out)
    lin_ratio = lin_out / np.maximum(lin_in, 1e-5)
    print(f"{label or os.path.basename(with_png)}: glass RGB {ins.round(3)}  world RGB {out.round(3)} "
          f"(world disc r={rw:.1f} at {bx},{by}, texture match {best:.2f})")
    print(f"  world / scope, as shown: R {out[0] / max(ins[0], 1e-4):.3f} G {out[1] / max(ins[1], 1e-4):.3f} B {out[2] / max(ins[2], 1e-4):.3f}")
    print(f"  world / scope, in light:  R {lin_ratio[0]:.3f} G {lin_ratio[1]:.3f} B {lin_ratio[2]:.3f}   "
          f"brightness {lin_out.mean() / max(lin_in.mean(), 1e-5):.3f}; colour of the gap (B/R) {lin_ratio[2] / lin_ratio[0]:.3f}")
    if log:
        new = not os.path.exists(log)
        with open(log, "a", encoding="utf-8") as f:
            if new:
                f.write("label\tlum_out\tin_r\tin_g\tin_b\tout_r\tout_g\tout_b\tlin_ratio_r\tlin_ratio_g\tlin_ratio_b\n")
            f.write("\t".join([label or os.path.basename(with_png), f"{float(lum_b[d2 < rw].mean()):.4f}"] +
                              [f"{v:.4f}" for v in list(ins) + list(out) + list(lin_ratio)]) + "\n")
    return 0


def locate(with_png, without_png, cx, cy, r, zoom=4.0, mark=None):
    """where in the rifle-lowered picture the glass's content really is: the glass disc shrunk by the zoom is searched
    over the whole picture by normalised cross-correlation (luminance), upright and turned 180 degrees (the scope's
    picture may be mirrored both ways: flip_h / flip_v in the scope's status file). Prints the best spot, its score and
    the orientation; --mark saves the lowered picture with the spot circled."""
    import numpy as np
    from PIL import Image, ImageDraw
    a = load_rgb(with_png)
    b = load_rgb(without_png)
    side = int(r * INNER)
    glass = a[int(cy - side):int(cy + side), int(cx - side):int(cx + side)]
    n = max(6, int(round(2 * side / zoom)))
    g = np.asarray(Image.fromarray((glass * 255).astype("uint8")).resize((n, n), Image.BOX)).astype("float32") / 255.0
    gl = g @ np.array([0.2126, 0.7152, 0.0722], dtype="float32")
    yy, xx = np.mgrid[0:n, 0:n]
    inside = ((xx - n / 2 + 0.5) ** 2 + (yy - n / 2 + 0.5) ** 2) <= (n / 2) ** 2
    bl = b @ np.array([0.2126, 0.7152, 0.0722], dtype="float32")
    H, W = bl.shape
    best = None
    for name, tpl in (("upright", gl), ("turned 180", gl[::-1, ::-1]), ("mirrored left-right", gl[:, ::-1]), ("mirrored up-down", gl[::-1, :])):
        t = tpl[inside]
        t = (t - t.mean()) / (t.std() + 1e-6)
        # sliding windows, stepping 2 px: enough to land within a pixel or two of the best spot
        for py in range(0, H - n, 2):
            rows = bl[py:py + n]
            for px in range(0, W - n, 2):
                p = rows[:, px:px + n][inside]
                sd = p.std()
                if sd < 0.01:
                    continue
                score = float((((p - p.mean()) / sd) * t).mean())
                if best is None or score > best[0]:
                    best = (score, px + n / 2, py + n / 2, name)
    if best is None:
        print("no match")
        return 1
    print(f"glass content found at ({best[1]:.0f}, {best[2]:.0f}) in the lowered picture, score {best[0]:.2f}, {best[3]}; "
          f"patch {n}x{n} px (zoom {zoom})")
    if mark:
        im = Image.open(without_png).convert("RGB")
        dr = ImageDraw.Draw(im)
        dr.ellipse((best[1] - n / 2, best[2] - n / 2, best[1] + n / 2, best[2] + n / 2), outline=(0, 255, 0), width=3)
        dr.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(255, 0, 0), width=2)
        im.save(mark)
    return 0


def srgb_to_linear(c):
    import numpy as np
    c = np.asarray(c)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def fit(tsv):
    """one gain, or a curve? Fits ln(ratio) = k0 + k1 * ln(outside brightness) per channel: k1 near 0 = one gain
    (trim); k1 away from 0 = the gap grows or shrinks with brightness (the curve's shape or the exposure)."""
    import numpy as np
    rows = [l.rstrip("\n").split("\t") for l in open(tsv, encoding="utf-8") if l.strip()]
    head, rows = rows[0], rows[1:]
    if len(rows) < 2:
        print("need at least two spots")
        return 1
    lum = np.array([float(r[1]) for r in rows])
    for ch, col in (("R", 8), ("G", 9), ("B", 10)):
        ratio = np.array([float(r[col]) for r in rows])
        x, y = np.log(np.maximum(lum, 1e-4)), np.log(np.maximum(ratio, 1e-4))
        k1, k0 = np.polyfit(x, y, 1) if len(rows) > 1 else (0.0, y.mean())
        print(f"{ch}: mean world/scope {np.exp(y.mean()):.3f}; with brightness: slope {k1:+.3f} "
              f"({'one gain fits' if abs(k1) < 0.15 else 'changes with brightness: the curve, not a gain'})")
    return 0


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    cmd, rest = argv[0], argv[1:]
    if cmd == "shot" and rest:
        eye = rest[rest.index("--eye") + 1] if "--eye" in rest else "left"
        return shot(rest[0], eye)
    if cmd == "find" and rest:
        return find(rest[0])
    if cmd == "compare" and len(rest) >= 4:
        label = rest[rest.index("--label") + 1] if "--label" in rest else ""
        log = rest[rest.index("--log") + 1] if "--log" in rest else None
        sector = None
        if "--sector" in rest:
            i = rest.index("--sector")
            sector = (float(rest[i + 1]), float(rest[i + 2]))
        return compare(rest[0], float(rest[1]), float(rest[2]), float(rest[3]), label, log, sector)
    if cmd == "compare2" and len(rest) >= 5:
        label = rest[rest.index("--label") + 1] if "--label" in rest else ""
        log = rest[rest.index("--log") + 1] if "--log" in rest else None
        zoom = float(rest[rest.index("--zoom") + 1]) if "--zoom" in rest else 4.0
        return compare2(rest[0], rest[1], float(rest[2]), float(rest[3]), float(rest[4]), zoom, label, log)
    if cmd == "locate" and len(rest) >= 5:
        zoom = float(rest[rest.index("--zoom") + 1]) if "--zoom" in rest else 4.0
        mark = rest[rest.index("--mark") + 1] if "--mark" in rest else None
        return locate(rest[0], rest[1], float(rest[2]), float(rest[3]), float(rest[4]), zoom, mark)
    if cmd == "fit" and rest:
        return fit(rest[0])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
