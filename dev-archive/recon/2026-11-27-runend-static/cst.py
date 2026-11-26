import rdis,re,pickle,ripx,lit,sys
s=pickle.load(open('sites.pkl','rb')); d=pickle.load(open('lits.pkl','rb'))
ins=rdis.dis(0x142b0af90,0x142b12f0c)
pos={x.address:i for i,x in enumerate(ins)}
names={}
for idx,sites in s.items():
    for a in sites:
        if a in pos:
            for x in ins[pos[a]+1:pos[a]+20]:
                mm=re.match(r'dword ptr \[rip \+ (0x[0-9a-f]+)\], eax',x.op_str)
                if x.mnemonic=='mov' and mm:
                    names[x.address+x.size+int(mm.group(1),16)]=d[idx]; break
pickle.dump(names,open('statehash.pkl','wb'))
print(len(names))
want=sys.argv[1:]
tg=[a for a,n in names.items() if n in want]
r=ripx.xrefs(tg)
for a in tg:
    print(names[a],hex(a))
    for x in r[a]:
        f,e=rdis.func_of(x); print('    ',hex(x),'func',hex(f))
