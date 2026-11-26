import importlib.util,sys,struct,os
spec=importlib.util.spec_from_file_location("t",os.path.expanduser("~/github-backups-pd/flat-to-vr-RE-toolkit/tools/tdb-read.py"));tm=importlib.util.module_from_spec(spec);spec.loader.exec_module(tm)
t=tm.Tdb("C:/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE/re8.exe")
at=t.base
ptrs=struct.unpack_from("<17Q",t.m,at+0x58)
p_intern=at+ptrs[16]
hdr=struct.unpack_from("<24I",t.m,at)
def lit(i):
    o=struct.unpack_from("<i",t.m,p_intern+i*4)[0]
    return o
def s_at(o):
    # try utf8 string pool then utf16 in bytes
    return t.string(o)
if __name__=="__main__":
    print([hex(h) for h in hdr])
    for i in (0x24da,0x390d,0x390e):
        o=lit(i); print(hex(i),o,repr(t.string(o)), repr(bytes(t.m[t.p_bytes+o:t.p_bytes+o+24])))
