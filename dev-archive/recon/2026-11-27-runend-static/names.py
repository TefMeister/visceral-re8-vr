import lit,pickle,os
t=lit.t
if not os.path.exists('meth.pkl'):
    out=[]
    for i,n in t.all_types():
        rec=t.type_record(i)
        if not rec["member_method"]: continue
        _n,_ns,nm,_nf=t.type_impl(rec["impl"])
        for k in range(nm):
            mi=rec["member_method"]+k
            out.append((t.method(mi)["name"],n,mi))
    pickle.dump(out,open('meth.pkl','wb'))
out=pickle.load(open('meth.pkl','rb'))
print(len(out))
import sys
lo,hi=sys.argv[1],sys.argv[2]
sel=sorted((m,c) for m,c,i in out if lo<m<hi and c.startswith('app.'))
print(len(sel))
import collections
for m,c in sel[:80]: print(m,c)
