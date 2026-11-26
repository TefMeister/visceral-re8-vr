import sys,struct,numpy as np,mmap,capstone
f=open("C:/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE/re8.exe",'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ)
base=0x140000000
pd=np.frombuffer(m,dtype='<u4',count=0x585918//4,offset=0xc3b8e00).reshape(-1,3)
starts=pd[:,0].astype(np.int64); ends=pd[:,1].astype(np.int64)
def func_of(va):
    rva=va-base; k=np.searchsorted(starts,rva,side='right')-1
    return base+int(starts[k]), base+int(ends[k])
def off(va):
    rva=va-base
    for va0,vs,ro in ((0x1000,0x7202977,0x400),(0x7204000,0xebc08e,0x7202e00),(0x80c1000,0x42f9e00,0x80bf000)):
        if va0<=rva<va0+vs: return ro+rva-va0
md=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_64)
def dis(s,e):
    code=m[off(s):off(s)+(e-s)]
    return list(md.disasm(code,s))
if __name__=="__main__":
    va=int(sys.argv[1],0); s,e=func_of(va)
    print('func',hex(s),hex(e),e-s)
    ins=dis(s,e)
    lo=int(sys.argv[2],0) if len(sys.argv)>2 else 40
    idx=[i for i,x in enumerate(ins) if x.address<=va<x.address+x.size]
    c=idx[0] if idx else 0
    for x in ins[max(0,c-lo):c+lo]:
        print(hex(x.address),x.mnemonic,x.op_str)
