import csv, json, itertools
from dims import DIMS
from reqs import P0,P1,TITLE
from coverage import COV, V
from scores import S
from longlist import LL
NAMES={"OCL":"OpenClaw","CCC":"cc-connect","AION":"AionUi+AionCore","ASB":"AstrBot","ACPX":"acpx","PPC":"Paperclip","ORC":"Orca",
"WCB":"WechatClawbot","PTG":"PentAGI","HDS":"Hindsight","BF":"BettaFish","OLD":"旧内部项目"}
ROLE={"OCL":"A","CCC":"A","AION":"A","ASB":"A","PPC":"A","ORC":"A","OLD":"A(承载仓)","ACPX":"B","WCB":"B","PTG":"B","HDS":"B","BF":"B"}
GAP={"OCL":["R-102","R-103","R-105","R-106","R-107","R-110","R-311"],
"CCC":["R-301","R-302","R-303","R-304","R-306","R-307","R-209","R-311","R-504","R-505"],
"AION":["R-601","R-603","R-604","R-605","R-606","R-607","R-608","R-609","R-610"],
"ASB":["R-301","R-302","R-303","R-304","R-306","R-307","R-104","R-105","R-311"],
"ACPX":["R-201","R-202","R-203","R-204","R-207","R-208","R-209","R-210","R-504","R-505"],
"PPC":["R-201","R-202","R-203","R-204","R-206","R-207","R-208","R-210","R-501","R-504","R-505","R-603","R-606","R-607"],
"ORC":["R-201","R-202","R-207","R-208","R-210","R-501","R-502","R-504","R-505","R-601","R-605","R-608","R-610"],
"WCB":["R-302","R-307","R-309"],
"PTG":["R-601","R-603","R-604","R-605","R-606","R-607","R-608","R-609","R-610"],
"OLD":["R-112","R-601","R-602","R-603","R-605","R-606","R-607","R-608","R-610","R-611"]}
EXTRA_B={"HDS":(["R-506","R-507","R-508","R-509"],"●●◐●"),"BF":(["R-603","R-604","R-924"],"◐◐◐")}
def anchor(p,p0full=False):
    if p>=0.85 and p0full: return 5
    if p>=0.65: return 4
    if p>=0.50: return 3
    if p>=0.30: return 2
    if p>=0.10: return 1
    return 0
cov={}
for k,(a,b) in COV.items():
    m=dict(zip(P0+P1,list(a)+list(b)))
    p0=sum(V[m[r]] for r in P0)/len(P0); p1=sum(V[m[r]] for r in P1)/len(P1); al=sum(V[m[r]] for r in P0+P1)/(len(P0)+len(P1))
    if k in EXTRA_B:
        ids,sy=EXTRA_B[k]; gb=sum(V[c] for c in sy)/len(sy)
    else:
        gb=sum(V[m[r]] for r in GAP[k])/len(GAP[k])
    cov[k]=dict(map=m,p0=p0,p1=p1,all=al,p0full=all(m[r]=="●" for r in P0),gapB=gb,
                p0p1_60= p0==1 and al>=0.6)
rows=[]; final={}
for k in COV:
    sc={}; ev={}; note={}; flags=[]
    sc["D01"]=anchor(cov[k]["all"],cov[k]["p0full"]); ev["D01"]="E4"
    note["D01"]=f"P0 {cov[k]['p0']*100:.1f}% / P1 {cov[k]['p1']*100:.1f}% / P0+P1 {cov[k]['all']*100:.1f}%（53 项矩阵）"
    for d,(s,e,n) in S[k].items():
        sc[d]=s; ev[d]=e; note[d]=n
    # G4
    for d in sc:
        if ev[d] in ("E0","E1","E2","E3") and sc[d]>3:
            note[d]+="【G4 封顶 3】"; sc[d]=3
    if sc["D17"]<=1: flags.append("G1"); sc["D08"]=min(sc["D08"],1)
    if sc["D23"]==0: flags.append("G2")
    if sc["D18"]==0: flags.append("G3")
    if sc["D16"]==0: flags.append("G5")
    if not cov[k]["p0full"]: flags.append("G6*")
    scB=dict(sc); scB["D01"]=anchor(cov[k]["gapB"],True if cov[k]["gapB"]>=0.85 else False)
    A=sum(sc[d]/5*wa for d,_,wa,wb in DIMS); B=sum(scB[d]/5*wb for d,_,wa,wb in DIMS)
    final[k]=dict(sc=sc,scB=scB,ev=ev,note=note,flags=flags,A=round(A,1),B=round(B,1))
# long list
for (n,d01,d17,d18,d19,d23,pct,desc) in LL:
    sc={d:2 for d,_,_,_ in DIMS}; sc.update(D01=min(d01,3),D17=d17,D18=d18,D19=min(d19,3),D23=min(d23,3))
    flags=[]
    if d17<=1: flags.append("G1"); sc["D08"]=1
    if d18==0: flags.append("G3")
    A=sum(sc[d]/5*wa for d,_,wa,wb in DIMS); B=sum(sc[d]/5*wb for d,_,wa,wb in DIMS)
    final["LL:"+n]=dict(sc=sc,scB=sc,flags=flags+["README级"],A=round(A,1),B=round(B,1),pct=pct,desc=desc)
# sensitivity (档A)
def wsum(sc,w): return sum(sc[d]/5*w[d] for d in w)
WA={d:wa for d,_,wa,_ in DIMS}
core=[k for k in COV]
eligible=[k for k in core if not ({"G1","G2","G3"}&set(final[k]["flags"]))]
def rank(w,pool):
    t=sum(w.values()); w={d:v*100/t for d,v in w.items()}
    r=sorted(pool,key=lambda k:-wsum(final[k]["sc"],w)); return r,[round(wsum(final[k]["sc"],w),1) for k in r]
base_all,_=rank(WA,core); base_el,_=rank(WA,eligible)
sens=[("基线",)+tuple(rank(WA,core))+tuple(rank(WA,eligible))]
eq={d:100/26 for d in WA}; sens.append(("等权重",)+tuple(rank(eq,core))+tuple(rank(eq,eligible)))
top=["D01","D09","D10","D16","D03","D06","D19"]
for d in top:
    for f in (1.3,0.7):
        w=dict(WA); w[d]*=f; sens.append((f"{d}×{f}",)+tuple(rank(w,core))+tuple(rank(w,eligible)))
out=dict(final={k:{kk:vv for kk,vv in v.items() if kk!='note' and kk!='ev'} for k,v in final.items()},
         cov={k:{kk:vv for kk,vv in v.items() if kk!='map'} for k,v in cov.items()},
         sens=[(s[0],s[1][:4],s[2][:4],s[3][:4],s[4][:4]) for s in sens], eligible=eligible)
json.dump(out,open("results.json","w"),ensure_ascii=False,indent=1)
json.dump({k:dict(note=v.get("note"),ev=v.get("ev")) for k,v in final.items() if not k.startswith("LL:")},open("notes.json","w"),ensure_ascii=False,indent=1)
json.dump({k:v["map"] for k,v in cov.items()},open("covmap.json","w"),ensure_ascii=False,indent=1)
# CSVs
with open("weights.csv","w",newline="",encoding="utf-8-sig") as f:
    w=csv.writer(f); w.writerow(["ID","维度","档A权重","档B权重"]); [w.writerow(d) for d in DIMS]
with open("scores.csv","w",newline="",encoding="utf-8-sig") as f:
    w=csv.writer(f); w.writerow(["候选","角色"]+[d for d,_,_,_ in DIMS]+["档A加权","档B加权","否决/封顶"])
    for k,v in final.items():
        w.writerow([NAMES.get(k,k),ROLE.get(k,"长名单")]+[v["sc"][d] for d,_,_,_ in DIMS]+[v["A"],v["B"],";".join(v["flags"])])
with open("coverage.csv","w",newline="",encoding="utf-8-sig") as f:
    w=csv.writer(f); w.writerow(["R","优先级","需求"]+[NAMES[k] for k in COV])
    for r in P0+P1: w.writerow([r,"P0" if r in P0 else "P1",TITLE[r]]+[cov[k]["map"][r] for k in COV])
for k,v in final.items():
    print(f"{NAMES.get(k,k):28s} A={v['A']:5} B={v['B']:5} {v['flags']} D01={v['sc']['D01']} D01B={v['scB']['D01']}")
for k in COV: print(k, {x:round(y,3) if isinstance(y,float) else y for x,y in cov[k].items() if x!='map'})
for s in sens: print(s[0], s[1][:3], s[2][:3], '| eligible', s[3][:3], s[4][:3])
