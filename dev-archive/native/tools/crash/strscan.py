import sys, re, mmap
exe = sys.argv[1]
pats = [p.encode() for p in sys.argv[2:]]
f = open(exe, 'rb')
m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
seen = set()
for p in pats:
    for enc in (p, p.decode().encode('utf-16le')):
        for mo in re.finditer(re.escape(enc), m):
            s = mo.start()
            wide = enc != p
            # expand to the whole string
            a = s
            step = 2 if wide else 1
            while a - step >= 0 and 0x20 <= m[a - step] < 0x7f and (not wide or m[a - step + 1] == 0): a -= step
            b = mo.end()
            while b < len(m) and 0x20 <= m[b] < 0x7f and (not wide or m[b + 1] == 0): b += step
            raw = m[a:b]
            txt = raw.decode('utf-16le' if wide else 'latin1')
            if txt not in seen:
                seen.add(txt)
                print("%09X %s %s" % (a, 'W' if wide else 'A', txt[:200]))
