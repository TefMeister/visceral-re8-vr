"""zone_sizes.py -- size every LG zone of the gun in hand as big as it can be without touching its neighbours (2026-11-04).

Tefa, 2026-11-04: "please also tweak the activation zones to be big enough just to not interfere with each other wherever
possible". The zones script (lua/visceral_re8_zones.lua) writes each zone's centre into zones_state.json; distances between
centres do not depend on the frame, so world centres are enough. For the zones the left grip can take at the same moment
(the magazine, the slide / pump / bolt, the slide from the left, the front grip, the handle, the drum, the breech), each
pair gets radii that add up to their distance minus a gap (GAP_CM), shared in proportion to the radii they have now; a
zone is never made bigger than MAX_CM or smaller than MIN_CM, and a zone with room to spare grows to MAX_CM.
The WELL (where a held magazine goes back in) is left alone: it only counts while a magazine is in the hand, when the
others do not.

    python zone_sizes.py            show the plan for the gun in hand
    python zone_sizes.py --write    also write the radii into zones.json for that gun (a backup is kept beside it)
"""
import json
import math
import os
import shutil
import sys
import time

D = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE\reframework\data\visceral_re8"
TAKES = {"mag", "slide", "pump", "bolt", "slide-left", "grip", "handle", "drum", "insert"}
GAP_CM = 1.5      # air between two neighbouring spheres
MIN_CM = 4.0      # below this a zone is too fiddly to find in the headset
MAX_CM = 14.0     # the largest zone today (the LEMI's slide 14.1); bigger reaches across the gun
SAME = {"slide", "slide-left"}   # the two sides of one slide: both take it (the side picks the hold), so they may overlap
# pairs the code already tells apart by what is going on, so their spheres may overlap: the F2's bolt counts only while a rack
# is due, and then it wins over the magazine (rack.cpp bolt_wants_left, 2026-11-01)
BY_STATE = [{"bolt", "mag"}]
GROW = 1.4        # a zone with room to spare grows, but at most to 1.4 x its size now (Tefa's own tuning keeps its shape)
PUMPS = {"3021", "3085", "3036", "3084", "3147"}   # zones.json names the PART zone by its kind (zones.cpp key_name):
BOLTS = {"3042", "3087"}                         # "pump" on the shotguns, "bolt" on the F2, "slide" on the pistols


def main():
    st = json.load(open(os.path.join(D, "zones_state.json"), encoding="utf-8"))
    gun = str(st.get("gun", 0))
    # a pump gun's WELL is its shell port: a shell in the left hand goes in there, next to the pump, so it is sized with the rest;
    # on a magazine gun the well is the magazine's own place and only counts with a magazine in the hand (left alone)
    takes = TAKES | ({"well"} if gun in PUMPS else set())
    zs = {z["key"]: z for z in st["zones"] if z.get("on") and z["key"] in takes and "x" in z}
    fixed = {}
    if gun == "0" or not zs:
        sys.exit("no gun in hand, or the zones script has not written centres yet (zones_state.json)")
    keys = sorted(zs)
    r = {k: zs[k]["r_cm"] for k in keys}
    c = {k: (zs[k]["x"] * 100, zs[k]["y"] * 100, zs[k]["z"] * 100) for k in keys}
    new = {k: min(MAX_CM, r[k] * GROW) for k in keys}
    for a in keys:
        for b in keys:
            if a >= b or {a, b} == SAME or {a, b} in BY_STATE:
                continue
            d = math.dist(c[a], c[b])
            room = max(0.0, d - GAP_CM)
            share = r[a] / (r[a] + r[b]) if r[a] + r[b] > 0 else 0.5
            new[a] = min(new[a], room * share)
            new[b] = min(new[b], room * (1 - share))
    for k, z in fixed.items():
        fc = (z["x"] * 100, z["y"] * 100, z["z"] * 100)
        for a in keys:
            new[a] = min(new[a], max(0.0, math.dist(c[a], fc) - GAP_CM - z["r_cm"]))
            print(f"  ({a} is {math.dist(c[a], fc):.1f} cm from the {k}, which keeps {z['r_cm']:.1f} cm)")
    print(f"gun {gun}:")
    for a in keys:
        near = sorted((math.dist(c[a], c[b]), b) for b in keys if b != a and {a, b} != SAME and {a, b} not in BY_STATE)
        n = f"nearest {near[0][1]} {near[0][0]:.1f} cm" if near else "alone"
        new[a] = max(MIN_CM, new[a])
        print(f"  {a:10s} {r[a]:5.1f} -> {new[a]:5.1f} cm   ({n})")
    clash = [(a, b) for a in keys for b in keys if a < b and {a, b} != SAME and {a, b} not in BY_STATE and new[a] + new[b] > math.dist(c[a], c[b])]
    for a, b in clash:
        print(f"  CLASH: {a} and {b} still touch (both at the {MIN_CM} cm floor: {math.dist(c[a], c[b]):.1f} cm apart)")
    if "--write" not in sys.argv:
        return
    p = os.path.join(D, "zones.json")
    shutil.copy2(p, p + time.strftime(".bak-%Y%m%d-%H%M%S"))
    cfg = json.load(open(p, encoding="utf-8"))
    g = cfg.setdefault(gun, {})
    for k in keys:
        name = k
        if k in ("slide", "pump", "bolt"):
            name = "pump" if gun in PUMPS else "bolt" if gun in BOLTS else "slide"
        g.setdefault(name, {})["r"] = round(new[k] / 100, 3)
    json.dump(cfg, open(p, "w", encoding="utf-8"), separators=(",", ":"))
    print("written to zones.json (backup beside it); the plugin re-reads it within half a second")


if __name__ == "__main__":
    main()
