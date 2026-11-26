import sys,numpy as np,rdis
m=rdis.m
text=np.frombuffer(m,dtype=np.uint8,count=0x7202a00,offset=0x400)
def xrefs(targets):
    # rel32 at every byte offset
    out={t:[] for t in targets}
    n=len(text)-4
    CH=1<<24
    for s in range(0,n,CH):
        e=min(n,s+CH)
        b=text[s:e+3].astype(np.int64)
        v=(b[:e-s]|(b[1:e-s+1]<<8)|(b[2:e-s+2]<<16)|(b[3:e-s+3]<<24))
        v=np.where(v>=1<<31,v-(1<<32),v)
        va=0x140001000+np.arange(s,e,dtype=np.int64)
        dest=va+4+v
        for t in targets:
            for k in np.where(dest==t)[0]: out[t].append(int(va[k]))
    return out
if __name__=="__main__":
    ts=[int(x,0) for x in sys.argv[1:]]
    r=xrefs(ts)
    for t in ts:
        print(hex(t))
        for a in r[t]:
            f,e=rdis.func_of(a); print('   ',hex(a),'in',hex(f),e-f)
