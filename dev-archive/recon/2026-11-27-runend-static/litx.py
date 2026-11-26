import sys,struct,re,pickle,os
import lit, rdis
t=lit.t; m=rdis.m
n=struct.unpack_from("<24I",t.m,t.base)  # find count: scan until bad
names={}
def build():
    if os.path.exists('lits.pkl'): return pickle.load(open('lits.pkl','rb'))
    d={}
    i=0
    while i<400000:
        o=lit.lit(i)
        if o<0 or o>t.n_bytes+50_000_000: break
        try: d[i]=t.string(o)
        except Exception: break
        i+=1
    pickle.dump(d,open('lits.pkl','wb')); return d
def sites():
    if os.path.exists('sites.pkl'): return pickle.load(open('sites.pkl','rb'))
    out={}
    tgt=0x14118c3c0; lo=0x400; hi=0x400+0x7202a00; i=lo
    while True:
        i=m.find(b'\xe8',i,hi)
        if i<0: break
        va=0x140001000+i-0x400
        rel=struct.unpack_from('<i',m,i+1)[0]
        if va+5+rel==tgt and m[i-5]==0xb9:
            idx=struct.unpack_from('<I',m,i-4)[0]
            out.setdefault(idx,[]).append(va-5)
        i+=1
    pickle.dump(out,open('sites.pkl','wb')); return out
if __name__=="__main__":
    d=build(); s=sites()
    print(len(d),'literals',len(s),'used')
    rx=re.compile(sys.argv[1])
    for i,v in d.items():
        if rx.search(v):
            fs={}
            for a in s.get(i,[]):
                f=rdis.func_of(a)[0]; fs.setdefault(f,[]).append(a)
            print(hex(i),repr(v),len(s.get(i,[])),' '.join('%x(%d)'%(f,len(a)) for f,a in sorted(fs.items())))
