"""zonemap.py [gun number ...] -- where a gun's grip zones start, end and overlap, by numbers (Tefa 2026-11-23: "where the grip
zones start and end and overlap"). Reads the game's zones_state.json (the gun in hand, live: centres in the world, sizes) (the game must
run; zones.json cannot be used: it holds slider offsets, not places). For each pair: how far the
centres are apart, how much the two balls overlap (cm, negative = a gap), and which one a hand midway between them is nearer to
its centre of (the mod gives the hand to the nearer part unless a rule says otherwise)."""
import json, os, sys, itertools, math
GAME = os.environ.get("RV_GAME_DIR", r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE")
D = os.path.join(GAME, "reframework", "data", "visceral_re8")
NAMES = {"3046": "LEMI", "3040": "M1911", "3047": "V61 Custom", "3050": "S.T.A.K.E", "3122": "Samurai Edge", "3124": "USM-AI", "3042": "F2 Rifle",
         "3049": "WCX", "3125": "Dragoon", "3048": "SYG-12", "3021": "W870 TAC", "3036": "M1897", "3116": "Handcannon PZ", "3008": "M1851 Wolfsbane", "3023": "GM 79"}
def table(title, zs):
    print("== %s" % title)
    for k, z in zs.items(): print("   %-10s centre %6.1f %6.1f %6.1f cm, reach %4.1f cm" % (k, z[0] * 100, z[1] * 100, z[2] * 100, z[3] * 100))
    for (a, za), (b, zb) in itertools.combinations(zs.items(), 2):
        d = math.dist(za[:3], zb[:3]); ov = za[3] + zb[3] - d
        inside = " (%s's centre lies INSIDE %s)" % (a, b) if d < zb[3] else ""
        inside += " (%s's centre lies INSIDE %s)" % (b, a) if d < za[3] else ""
        print("   %-10s / %-10s %5.1f cm apart, %s%s" % (a, b, d * 100, ("overlap %.1f cm" % (ov * 100)) if ov > 0 else ("gap %.1f cm" % (-ov * 100)), inside))
args = sys.argv[1:]
if not args:
    d = json.load(open(os.path.join(D, "zones_state.json")))
    table("gun %s in hand (live)" % d.get("gun"), {z["key"]: (z["x"], z["y"], z["z"], z["r_cm"] / 100.0) for z in d["zones"] if z.get("on")})
else:
    # 2026-11-23: zones.json holds each zone's SLIDER OFFSET from its own part, not its place: a table made from it is wrong
    # (the F2's four zones came out "0 cm apart"). The places exist only while the game runs: equip the gun, run with no number.
    print("zones.json holds slider offsets, not places: run with no argument while the game runs with the gun in hand"); sys.exit(1)
