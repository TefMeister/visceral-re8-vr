import rdis,sys,re,fl
def show(a,b=None,mark=None):
    if b is None:
        f=fl.funcs(a,a+0x8000); b=f[1] if len(f)>1 else a+0x400
    for x in rdis.dis(a,b):
        s=x.op_str
        mm=re.search(r'rip ([+-]) (0x[0-9a-f]+)',s)
        if mm: s+='   ; ->'+hex(x.address+x.size+(int(mm.group(2),16) if mm.group(1)=='+' else -int(mm.group(2),16)))
        print(hex(x.address),x.mnemonic,s)
if __name__=="__main__":
    a=int(sys.argv[1],0); b=int(sys.argv[2],0) if len(sys.argv)>2 else None
    show(a,b)
