"""compare.py -- recoil_test.cpp (the shipped C++) against recoil_test.lua (Andyalpa's original Lua), frame by frame.
   python compare.py cpp.csv lua.csv      exit 0 = every value within tolerance (float vs double)"""
import sys
def rows(p):
    out = {}
    for line in open(p, encoding="utf-8"):
        f = line.strip().split(",")
        if len(f) == 7: out[(f[0], int(f[1]))] = [float(x) for x in f[2:]]
    return out
a, b = rows(sys.argv[1]), rows(sys.argv[2])
assert a.keys() == b.keys() and a, "the two runs printed different frames"
worst, where, peak = 0.0, None, {}
for k in a:
    for i in range(5):
        d = abs(a[k][i] - b[k][i]); scale = max(abs(b[k][i]), 1e-3)
        peak[k[0]] = max(peak.get(k[0], 0.0), abs(b[k][0]))
        if d / scale > worst: worst, where = d / scale, (k, i, a[k][i], b[k][i])
for n, p in sorted(peak.items()): print(f"{n}: peak pitch {p:.5f} rad")
print(f"frames compared: {len(a)}; worst relative difference {worst:.2e} at {where}")
sys.exit(0 if worst < 1e-3 else 1)
