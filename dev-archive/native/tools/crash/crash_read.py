import sys, struct, logging
logging.disable(logging.CRITICAL)
from minidump.minidumpfile import MinidumpFile

path = sys.argv[1]
md = MinidumpFile.parse(path)
mods = sorted((m.baseaddress, m.baseaddress + m.size, m.name.split('\\')[-1]) for m in md.modules.modules)
def sym(a):
    for b, e, n in mods:
        if b <= a < e:
            return "%s+0x%X" % (n, a - b)
    return None
print("== ", path)
if '-m' in sys.argv:
    for b, e, n in mods:
        print("  %016X %8X %s" % (b, e - b, n))
exc = md.exception.exception_records[0]
f = open(path, 'rb')
f.seek(exc.ThreadContext.Rva)
raw = f.read(exc.ThreadContext.DataSize)
rsp = struct.unpack_from("<Q", raw, 0x98)[0]
segs = md.memory_segments.memory_segments
print("segments:")
tot = 0
for s in segs:
    tot += s.size
    if s.start_virtual_address <= rsp < s.start_virtual_address + s.size:
        seg = s
        print("  crash stack seg %X size %X" % (s.start_virtual_address, s.size))
print("  total bytes", tot)
f.seek(seg.start_file_address)
data = f.read(seg.size)
off0 = rsp - seg.start_virtual_address
n = 0
for off in range(off0, len(data) - 7, 8):
    q = struct.unpack_from("<Q", data, off)[0]
    s = sym(q)
    if s:
        print("  rsp+%04X %016X %s" % (off - off0, q, s))
    elif '-a' in sys.argv and off - off0 < 0x200:
        print("  rsp+%04X %016X" % (off - off0, q))
# which segments are not stacks? print any segment containing key heap addrs
for name, o in (("rbx", 0x90), ("rdx", 0x88), ("rbp", 0xA0), ("r13", 0xE0)):
    v = struct.unpack_from("<Q", raw, o)[0]
    for s in segs:
        if s.start_virtual_address <= v < s.start_virtual_address + s.size:
            f.seek(s.start_file_address + v - s.start_virtual_address)
            b = f.read(min(0x80, s.start_virtual_address + s.size - v))
            print(name, "%X in dump:" % v, b.hex())
            break
    else:
        print(name, "%X not in dump" % v)
