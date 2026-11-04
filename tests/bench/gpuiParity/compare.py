import sys, statistics as st, collections as C
side=None; t=C.defaultdict(list); cpu=C.defaultdict(list)
for line in open(sys.argv[1]):
    w=line.split()
    if line.startswith('=== '): side=w[1].split('-')[0]; continue
    if not side or not w: continue
    if w[0]=='SAMPLE':
        if side=='void': t[(w[1],w[3],side)].append(float(w[7]))
        else: t[(w[1],w[2],side)].append(float(w[10])/1e6)
    elif w[0]=='CPU_NS_WITH_HARNESS': cpu[(w[1],w[2],side)].append(float(w[4])/1e6)
def q(v,p): v=sorted(v); return v[min(len(v)-1,int(p*len(v)))]
print('case phase | frame ms med/p95: void gpui ratio | cpu ms med: void gpui ratio | n')
for c,ph in sorted({(k[0],k[1]) for k in t}, key=lambda k:(k[0],)):
    v,g=t[(c,ph,'void')],t[(c,ph,'gpui')]; cv,cg=cpu[(c,ph,'void')],cpu[(c,ph,'gpui')]
    if not v or not g: print(c,ph,'missing',len(v),len(g)); continue
    r=lambda a,b: f'{st.median(b)/st.median(a):.2f}x' if a and b else '-'
    print(f'{c:8} {ph:11} | {st.median(v):.3f}/{q(v,.95):.3f}  {st.median(g):.3f}/{q(g,.95):.3f}  {r(v,g)} | '
          f'{st.median(cv) if cv else 0:.3f} {st.median(cg) if cg else 0:.3f} {r(cv,cg)} | {len(v)},{len(g)}')
print('\nGPUI mutation+draw+present (no wait) vs Void totalMs, medians')
g2=C.defaultdict(list)
side=None
for line in open(sys.argv[1]):
    w=line.split()
    if line.startswith('=== '): side=w[1].split('-')[0]; continue
    if side=='gpui' and w and w[0]=='SAMPLE': g2[(w[1],w[2])].append((float(w[5])+float(w[6])+float(w[7]))/1e6)
for (c,ph),g in sorted(g2.items()):
    v=t[(c,ph,'void')]; print(f'{c:8} {ph:11} void {st.median(v):.3f}  gpui {st.median(g):.3f}  {st.median(g)/st.median(v):.2f}x')
