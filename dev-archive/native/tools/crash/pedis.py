"""dis.py <exe> <rva-hex> [bytes-hex]  : disassemble from a PE on disk at an RVA (addresses printed as RVAs).
   dis.py <exe> func <rva-hex>        : find the function start (via .pdata) that holds the RVA and print all of it."""
import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

exe = sys.argv[1]
f = open(exe, 'rb')
hdr = f.read(0x1000)
pe = struct.unpack_from("<I", hdr, 0x3C)[0]
nsec = struct.unpack_from("<H", hdr, pe + 6)[0]
optsz = struct.unpack_from("<H", hdr, pe + 20)[0]
opt = pe + 24
secs = []
so = opt + optsz
for i in range(nsec):
    name = hdr[so:so + 8].rstrip(b'\0').decode('latin1')
    vsz, va, rsz, raw = struct.unpack_from("<IIII", hdr, so + 8)
    secs.append((name, va, vsz, raw, rsz))
    so += 40
def r2o(rva):
    for n, va, vsz, raw, rsz in secs:
        if va <= rva < va + max(vsz, rsz):
            return raw + rva - va
    raise SystemExit("rva %X not in a section" % rva)
def read(rva, n):
    f.seek(r2o(rva)); return f.read(n)
# exception dir = data dir 3
exc_rva, exc_sz = struct.unpack_from("<II", hdr, opt + 112 + 3 * 8)
def func_bounds(rva):
    f.seek(r2o(exc_rva)); tab = f.read(exc_sz)
    n = exc_sz // 12
    lo, hi = 0, n - 1
    while lo <= hi:
        mid = (lo + hi) // 2
        b, e, u = struct.unpack_from("<III", tab, mid * 12)
        if rva < b: hi = mid - 1
        elif rva >= e: lo = mid + 1
        else: return b, e
    return None
cs = Cs(CS_ARCH_X86, CS_MODE_64)
def dis(rva, n, mark=None):
    code = read(rva, n)
    for i in cs.disasm(code, rva):
        print("%s %08X  %-8s %s" % (">>" if i.address == mark else "  ", i.address, i.mnemonic, i.op_str))
if sys.argv[2] == 'func':
    rva = int(sys.argv[3], 16)
    b = func_bounds(rva)
    if not b: raise SystemExit("no pdata entry")
    print("function %X..%X (%d bytes)" % (b[0], b[1], b[1] - b[0]))
    dis(b[0], min(b[1] - b[0], int(sys.argv[4], 16) if len(sys.argv) > 4 else 0x600), rva)
elif sys.argv[2] == 'secs':
    for s in secs: print("%-8s va %08X vsz %08X raw %08X rsz %08X" % s)
else:
    rva = int(sys.argv[2], 16)
    dis(rva, int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x100, rva)
