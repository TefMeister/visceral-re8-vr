import rdis,sys,numpy as np
m=rdis.m
st=np.sort(rdis.starts)
def funcs(lo,hi):
    out=[]
    for r in st[(st>=lo-0x140000000)&(st<hi-0x140000000)]:
        va=0x140000000+int(r); o=rdis.off(va)
        if va%16==0 and m[o-1] in (0xCC,0xC3,0x00,0x90) : out.append(va)
    return out
if __name__=="__main__":
    f=funcs(int(sys.argv[1],0),int(sys.argv[2],0))
    print(len(f)); print(' '.join(hex(x) for x in f))
