#!/usr/bin/env python3
"""scope_dump_read.py -- read the scope plugin's frozen pictures (numpad + in the headset) and try colour recipes on them.

WHY (2026-11-05, Tefa: balls of yarn, yellow paint, well pulleys and snow dust go "almost neon" in the scope while the
world and the rest of the scope look fine): in the headset the desktop window does not draw, so the world cannot be
photographed from the PC; but numpad + makes the scope plugin save, for one frame, the RAW scene light its camera saw
(`flicker-spike-N-src.ppm`, raw HDR stored as x/(1+x), which this file undoes) and the finished scope picture
(`flicker-spike-N-now.ppm`). From the raw light the whole scope recipe can be re-run here, with any change, and the
result shown as a picture, so a recipe is judged on the very frame Tefa froze, without another headset run per try.

  python scope_dump_read.py list                       the dump sets in the game's data folder (newest last)
  python scope_dump_read.py read N [--label yarn]      numbers at the glass centre: raw light, finished picture; previews
  python scope_dump_read.py render N [recipe knobs]    re-run the scope recipe on the raw light with changes, write a PNG
      --exposure-gt 10846.8  --ev 6.4  --wb -1.5  --trim 0.86,1.0,1.3  --contrast 1.0
      --exposure-scale 1.0   (x on the exposure: 0.6 = the measured 1.7x too bright undone)
      --trim-before          (the trim applied in the raw light, before the curve, so it can never clip)
      --curve perchannel|lum|linear (lum = one curve on the brightness, hue kept; linear = no curve of ours at all,
                             the plugin's tone_mode 2 since 2026-11-06: the texture the glass gets, clipped at 1.0)
      --out NAME             (the PNG's name)
All numbers are printed; the previews go to the dumps folder (local, never git).
"""
import argparse
import glob
import os
import re
import sys
import time

import numpy as np
from PIL import Image

GAME = None
for cand in glob.glob(r"C:\Steam\steamapps\common\*illage*"):
    GAME = cand
DATA = os.path.join(GAME, "reframework", "data") if GAME else None
OUT = r"D:\RE Village REFramework builds\scope-dumps"

# the game's own curve as the plugin logged it today (tone curve CHANGED ... 2026-11-05 14:56)
CURVE = dict(m=0.22, l=0.40, c=1.00, a=1.20, wp_min=5.6, wp_ref=5.6)
LUM_W = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
CENTRE_SMALL = 0.03     # the glass centre, as a share of the picture's short side
CENTRE_MID = 0.08
CENTRE_NOW = 0.12       # the finished picture is the lens alone, so a wider centre
CLIP_AT = 0.99
OVER_RANGE = 250.0      # the dump's encoding tops out near here


def gt_tonemap(x, P=1.0, a=1.2, m=0.22, l=0.4, c=1.0, b=0.0):
    """Uchimura's GT curve, the text of the plugin's tone_curve.inc, vectorised."""
    x = np.maximum(x, 0.0)
    l0 = ((P - m) * l) / a
    S0 = m + l0
    S1 = m + a * l0
    C2 = (a * P) / (P - S1)
    CP = -C2 / P
    t = np.clip(x / m, 0.0, 1.0)
    w0 = 1.0 - t * t * (3.0 - 2.0 * t)
    w2 = np.where(x < S0, 0.0, 1.0)
    w1 = 1.0 - w0 - w2
    T = m * np.power(x / m, c) + b
    S = P - (P - S1) * np.exp(CP * (x - S0))
    L = m + a * (x - m)
    return T * w0 + L * w1 + S * w2


def load_ppm(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float32) / 255.0


def undo_reinhard(y):
    """The dump stores raw HDR as x/(1+x); back to x. 255 means 'at least 254'."""
    y = np.minimum(y, 254.0 / 255.0)
    return y / (1.0 - y)


def sets():
    if not DATA:
        return []
    found = {}
    for p in glob.glob(os.path.join(DATA, "flicker-spike-*-src.ppm")):
        n = int(re.search(r"flicker-spike-(\d+)-src", p).group(1))
        found[n] = p
    return sorted(found.items(), key=lambda kv: os.path.getmtime(kv[1]))


def centre_stats(img, frac):
    h, w = img.shape[:2]
    r = int(min(h, w) * frac)
    cy, cx = h // 2, w // 2
    yy, xx = np.ogrid[:h, :w]
    mask = (yy - cy) ** 2 + (xx - cx) ** 2 <= r * r
    px = img[mask]
    return px.mean(axis=0), px.max(axis=0), np.percentile(px, 95, axis=0)


def lum(rgb):
    return rgb @ LUM_W


def preview(raw, path):
    """A quick look at the raw light: a simple exposure so the picture is readable, not the scope's recipe."""
    med = np.median(lum(raw)) + 1e-6
    img = 1.0 - np.exp(-raw * (0.4 / med))
    Image.fromarray((np.clip(img, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8)).save(path)


def clipped(y):
    return tuple(100.0 * np.mean(y[..., i] >= CLIP_AT) for i in range(3))


def cmd_list(_):
    found = sets()
    for n, p in found:
        now = p.replace("-src.ppm", "-now.ppm")
        stamp = time.strftime("%H:%M:%S", time.localtime(os.path.getmtime(p)))
        print(f"{n:5d}  {stamp}  src {os.path.getsize(p) // 1024} KB  now {'yes' if os.path.exists(now) else 'MISSING'}")
    if not found:
        print("no dump sets found (numpad + with the scope on the mirror writes one)")


def exposure_of(a):
    return a.exposure_gt * 0.4 * (2.0 ** -a.ev) * a.exposure_scale


def run_recipe(raw, a):
    """The scope's ps_main colour path on raw HDR (the sky fill left out: it only paints the black dome)."""
    col = raw.copy()
    wb = a.wb  # at EV 6.4 the white-balance gate is 1.0
    col *= np.array([1.0 - 0.18 * wb, 1.0 - 0.04 * wb, 1.0 + 0.14 * wb], dtype=np.float32)
    trim = np.array([float(v) for v in a.trim.split(",")], dtype=np.float32)
    if a.trim_before:
        col *= trim
    expo = exposure_of(a)
    wp = CURVE["wp_min"] / CURVE["wp_ref"]
    x = col * (expo / wp)
    k = dict(a=CURVE["a"], m=CURVE["m"], l=CURVE["l"], c=CURVE["c"])
    if a.curve == "linear":
        # 2026-11-06, the plugin's tone_mode 2: one gain, no curve of ours; the game's own curve tone-maps the glass
        # afterwards (not modelled here), so this picture is what the glass TEXTURE holds, clipped at 1.0 like it.
        y = x
    elif a.curve == "perchannel":
        y = gt_tonemap(x, **k)
    else:  # one curve on the brightness, the colour ratios kept, then the clip
        L = lum(x)[..., None]
        y = x * (gt_tonemap(L, **k) / np.maximum(L, 1e-6))
    if not a.trim_before:
        y *= trim
    y = (y - 0.5) * a.contrast + 0.5
    return np.clip(y, 0.0, 1.0)


def add_recipe_args(p):
    p.add_argument("--exposure-gt", type=float, default=10846.835938)
    p.add_argument("--ev", type=float, default=6.4)
    p.add_argument("--wb", type=float, default=-1.5)
    p.add_argument("--trim", default="0.86,1.0,1.3")
    p.add_argument("--contrast", type=float, default=1.0)
    p.add_argument("--exposure-scale", type=float, default=1.0)
    p.add_argument("--trim-before", action="store_true")
    p.add_argument("--curve", choices=["perchannel", "lum", "linear"], default="perchannel")


def find_set(n):
    for k, p in sets():
        if k == n:
            return p
    sys.exit(f"no dump set {n}")


def cmd_read(a):
    p = find_set(a.n)
    raw = undo_reinhard(load_ppm(p))
    now = load_ppm(p.replace("-src.ppm", "-now.ppm"))
    os.makedirs(OUT, exist_ok=True)
    tag = f"{a.n}-{a.label}" if a.label else str(a.n)
    preview(raw, os.path.join(OUT, f"{tag}-raw-preview.png"))
    Image.fromarray((now * 255).astype(np.uint8)).save(os.path.join(OUT, f"{tag}-now.png"))
    print(f"set {a.n} ({a.label or 'no label'}): raw {raw.shape[1]}x{raw.shape[0]}, finished {now.shape[1]}x{now.shape[0]}")
    for frac in (CENTRE_SMALL, CENTRE_MID):
        m, mx, p95 = centre_stats(raw, frac)
        print(f"  raw light, centre r={frac:.0%}: mean R {m[0]:.3f} G {m[1]:.3f} B {m[2]:.3f}"
              f" | 95% {p95[0]:.2f} {p95[1]:.2f} {p95[2]:.2f} | max {mx[0]:.1f} {mx[1]:.1f} {mx[2]:.1f}")
    m, mx, p95 = centre_stats(raw, 1.0)
    print(f"  raw light, whole picture: mean R {m[0]:.3f} G {m[1]:.3f} B {m[2]:.3f}"
          f" | 95% {p95[0]:.2f} {p95[1]:.2f} {p95[2]:.2f} | max {mx[0]:.1f} {mx[1]:.1f} {mx[2]:.1f}")
    L = lum(raw)
    print(f"  raw brightness: median {np.median(L):.3f}, 99% {np.percentile(L, 99):.2f},"
          f" share over the dump's range {100 * np.mean(L >= OVER_RANGE):.2f}%")
    m, mx, p95 = centre_stats(now, CENTRE_NOW)
    c = clipped(now)
    print(f"  finished scope picture, centre r={CENTRE_NOW:.0%}: mean R {m[0] * 255:.0f} G {m[1] * 255:.0f} B {m[2] * 255:.0f} (0-255)"
          f" | clipped share: R {c[0]:.1f}% G {c[1]:.1f}% B {c[2]:.1f}%")
    print(f"  previews: {OUT}\\{tag}-raw-preview.png  {OUT}\\{tag}-now.png")


def cmd_render(a):
    p = find_set(a.n)
    raw = undo_reinhard(load_ppm(p))
    y = run_recipe(raw, a)
    os.makedirs(OUT, exist_ok=True)
    name = a.out or f"{a.n}-render-x{a.exposure_scale:g}-{'trimbefore' if a.trim_before else 'trimafter'}-{a.curve}.png"
    Image.fromarray((y * 255).astype(np.uint8)).save(os.path.join(OUT, name))
    m, mx, p95 = centre_stats(y, CENTRE_SMALL)
    c = clipped(y)
    print(f"set {a.n} rendered: exposure {exposure_of(a):.2f} ({'trim before' if a.trim_before else 'trim after'} the curve, {a.curve})")
    print(f"  centre r={CENTRE_SMALL:.0%}: mean R {m[0] * 255:.0f} G {m[1] * 255:.0f} B {m[2] * 255:.0f}"
          f" | clipped share: R {c[0]:.1f}% G {c[1]:.1f}% B {c[2]:.1f}%")
    print(f"  picture: {OUT}\\{name}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list").set_defaults(f=cmd_list)
    r = sub.add_parser("read")
    r.add_argument("n", type=int)
    r.add_argument("--label", default="")
    r.set_defaults(f=cmd_read)
    d = sub.add_parser("render")
    d.add_argument("n", type=int)
    d.add_argument("--out", default="")
    add_recipe_args(d)
    d.set_defaults(f=cmd_render)
    a = ap.parse_args()
    a.f(a)


if __name__ == "__main__":
    main()
