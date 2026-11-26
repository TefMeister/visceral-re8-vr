import rdis,struct,numpy as np,sys,collections
m=rdis.m
st=np.sort(rdis.starts)
al=st[(st%16)==0]
def fn(va):
    k=np.searchsorted(al,va-0x140000000,side='right')-1
    return 0x140000000+int(al[k])
def find(disp):
    pat=struct.pack('<I',disp); out=collections.defaultdict(list); i=0x400
    while True:
        i=m.find(pat,i,0x400+0x7202a00)
        if i<0: break
        modrm=m[i-1]
        if (modrm>>6)==2 and (modrm&7) not in (4,5):   # [reg+disp32], no SIB
            op=m[i-2]; op2=m[i-3]
            out[fn(0x140001000+i-0x400)].append((0x140001000+i-0x400,'%02x%02x'%(op2,op)))
        i+=1
    return out
if __name__=="__main__":
    ds=[int(x,0) for x in sys.argv[1:]]
    r=[find(d) for d in ds]
    common=set(r[0])
    for x in r[1:]: common&=set(x)
    print([len(x) for x in r],len(common))
    for f in sorted(common): print(hex(f),[ (len(x[f])) for x in r])
