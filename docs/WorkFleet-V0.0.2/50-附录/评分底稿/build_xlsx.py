import re, json, csv, sys
from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill, Border, Side
from openpyxl.utils import get_column_letter
sys.argv=[sys.argv[0]]
import io, contextlib
with contextlib.redirect_stdout(io.StringIO()):
    from compute import final, cov, NAMES, ROLE, sens
from dims import DIMS
from reqs import P0,P1,TITLE
from meta import ORDER
ROOT="../../"
notes=json.load(open("notes.json",encoding="utf-8"))
cm=json.load(open("covmap.json",encoding="utf-8"))
def md_tables(path, header_startswith=None, after_marker=None, first_only=False):
    lines=open(ROOT+path,encoding="utf-8").read().split("\n")
    out=[];cur=None;armed=after_marker is None
    for i,l in enumerate(lines):
        if after_marker and after_marker in l: armed=True; continue
        if not armed: continue
        if l.startswith("|"):
            cells=[c.strip() for c in l.strip().strip("|").split("|")]
            if cur is None:
                cur=[cells]
            elif re.match(r"^\|[\s\-:|]+\|$",l.strip()):
                continue
            else: cur.append(cells)
        else:
            if cur:
                if header_startswith is None or cur[0][0].startswith(header_startswith): out.append(cur)
                cur=None
                if first_only and out: return out
    if cur and (header_startswith is None or cur[0][0].startswith(header_startswith)): out.append(cur)
    return out
def clean(s):
    return re.sub(r"\*\*|`","",s) if isinstance(s,str) else s
wb=Workbook(); wb.remove(wb.active)
HFILL=PatternFill("solid",fgColor="1F3A5F"); HFONT=Font(bold=True,color="FFFFFF")
thin=Side(style="thin",color="C8CDD3"); BORDER=Border(left=thin,right=thin,top=thin,bottom=thin)
def sheet(name, rows, widths=None, maxw=60):
    ws=wb.create_sheet(name)
    for r in rows: ws.append([clean(x) for x in r])
    for c in ws[1]: c.fill=HFILL; c.font=HFONT
    for row in ws.iter_rows():
        for c in row:
            c.alignment=Alignment(wrap_text=True,vertical="top"); c.border=BORDER
    ncol=max(len(r) for r in rows)
    for j in range(1,ncol+1):
        if widths and j-1<len(widths): w=widths[j-1]
        else:
            L=max((len(str(ws.cell(row=i,column=j).value or "")) for i in range(1,min(ws.max_row,60)+1)),default=8)
            w=min(max(8,L*1.1),maxw)
        ws.column_dimensions[get_column_letter(j)].width=w
    ws.freeze_panes="B2" if ncol>3 else "A2"
    ws.auto_filter.ref=ws.dimensions
    return ws
# 1 需求分解（各分区表头不同 → 以“【表头】”行分隔，保留原列）
rows=[["ID","列2","列3","列4","列5","列6","列7","列8","列9"]]
n=0
for t in md_tables("01-需求分解与分析规划/01-需求分解树.md"):
    if t[0][0]=="ID" and len(t)>1 and t[1][0].startswith("R-"):
        rows.append(["【表头】"]+t[0][1:])
        for r in t[1:]:
            if r[0].startswith("R-"): rows.append(r); n+=1
print("R rows",n)
sheet("需求分解",rows,[9,10,44,34,9,44,16,18,22])
# 2 候选评分(26维)
hdr=["ID","维度","档A权重","档B权重"]+[f"{k} {NAMES[k]}" for k in ORDER]
rows=[hdr]
for d,n,wa,wb_ in DIMS: rows.append([d,n,wa,wb_]+[final[k]["sc"][d] for k in ORDER])
rows.append(["—","档A加权",100,""]+[final[k]["A"] for k in ORDER])
rows.append(["—","档B加权","",100]+[final[k]["B"] for k in ORDER])
rows.append(["—","P0覆盖率","",""]+[f"{cov[k]['p0']*100:.1f}%" for k in ORDER])
rows.append(["—","P0+P1覆盖率","",""]+[f"{cov[k]['all']*100:.1f}%" for k in ORDER])
rows.append(["—","命中规则","",""]+[",".join(final[k]["flags"]) for k in ORDER])
rows.append(["","","",""]); rows.append(["候选","维度","分","证据等级/一行证据"])
for k in ORDER:
    for d,n,_,_ in DIMS:
        rows.append([f"{k} {NAMES[k]}",f"{d} {n}",final[k]["sc"][d],f"{notes[k]['ev'][d]}｜{notes[k]['note'][d]}"])
rows.append([]); rows.append(["长名单（README级）","档A","档B","说明"])
for k,v in final.items():
    if k.startswith("LL:"): rows.append([k[3:],v["A"],v["B"],v["desc"]+"；"+",".join(v["flags"])])
rows.append([]); rows.append(["敏感性扰动","全部前4","可作底座前4",""])
for s in sens: rows.append([s[0]," > ".join(s[1][:4])," > ".join(s[3][:4]),", ".join(map(str,s[2][:4]))])
ws=sheet("候选评分(26维)",rows,[16,16,8,8]+[12]*len(ORDER))
# 3 需求覆盖
rows=[["R","优先级","需求"]+[f"{k}" for k in ORDER]]
for r in P0+P1: rows.append([r,"P0" if r in P0 else "P1",TITLE[r]]+[cm[k][r] for k in ORDER])
rows.append(["","","P0覆盖率"]+[f"{cov[k]['p0']*100:.0f}%" for k in ORDER])
rows.append(["","","P1覆盖率"]+[f"{cov[k]['p1']*100:.0f}%" for k in ORDER])
rows.append(["","","P0+P1覆盖率"]+[f"{cov[k]['all']*100:.0f}%" for k in ORDER])
sheet("需求覆盖",rows,[8,7,26]+[7]*len(ORDER))
# 4 架构对比（02 §1–§6、§9）
rows=[["主题","项目","内容1","内容2","内容3","内容4","内容5","内容6","内容7"]]
sec_names=["架构形态与分层","进程/并发模型","数据模型","扩展机制","技术栈","实现路线与演进","关键链路","需求映射","可借鉴与不可借鉴"]
tabs=md_tables("40-综合/02-参考项目技术架构对比.md")
# skip first (一页结论)
for name,t in zip(["一页结论"]+sec_names,tabs):
    rows.append([name,"【表头】"]+t[0][1:])
    for r in t[1:]: rows.append([name]+r)
sheet("架构对比",rows,[14,16,40,40,40,40,30,30,30])
# 5 缺口补充
t=md_tables("40-综合/03-功能缺口与补充方案.md",after_marker="xlsx:缺口补充",first_only=True)[0]
sheet("缺口补充",t,[7,30,14,48,12,36,8,8,22,30])
# 6 KPI
rows=[]
for t in md_tables("01-需求分解与分析规划/05-验收标准与指标.md"):
    if t[0][0]=="ID" or t[0][0]=="编号":
        if t[1][0].startswith("K-"):
            if not rows: rows.append(t[0]+["V0.0.2 本轮证据"])
            rows+= [r for r in t[1:] if r[0].startswith("K-")]
ev={"K-47":"〔内部实测数据已移除〕","K-34":"20 万合成 FTS p95 1.7ms（部分确认）","K-11":"合成批量 15.4k 行/秒（单事务，非持续）",
    "K-22":"未测（PoC-1）；额度推演 25 条/天≈4 次入站","K-15":"推算 1 万人 TG 6.2 分钟","K-32":"holiday-cn 2027 为空→降级告警必须触发","K-04":"python-sdk 0.12.1 API 面完整，端到端未测","K-05":"未测"}
for r in rows[1:]:
    while len(r)<len(rows[0])-1: r.append("")
    r.append(ev.get(r[0],""))
sheet("KPI",rows,[7,18,28,26,24,30,10,14,30])
# 7 路线图
t1=md_tables("40-综合/09-路线图与PoC清单.md",after_marker="xlsx:路线图",first_only=True)[0]
tabs=md_tables("40-综合/09-路线图与PoC清单.md")
poc=[t for t in tabs if t[0][0]=="编号"][0]
dg=[t for t in tabs if t[0][0]=="闸门"][0]
rows=t1+[[]]+[["【PoC】"]+poc[0]]+[[""]+r for r in poc[1:]]+[[]]+[["【决策闸门】"]+dg[0]]+[[""]+r for r in dg[1:]]
sheet("路线图",rows,[12,24,44,30,40,12,14,12])
# 8 待裁定
tabs=md_tables("40-综合/10-待用户裁定清单.md")
rows=[["分组","编号","问题","推荐默认","影响/不选默认的影响","V0.0.2 证据/状态","影响文件"]]
for r in tabs[0][1:]: rows.append(["★ 必须裁定",r[0],r[1],r[2],r[3],r[4],r[5]])
for r in tabs[1][1:]: rows.append(["其他",r[0],r[1],r[2],r[3],r[4],""])
for r in tabs[2][1:]: rows.append(["已由证据裁定",r[0],r[1],r[2],"",r[3],""])
sheet("待裁定",rows,[12,10,30,48,40,36,12])
out=ROOT+"40-综合/WorkFleet-V0.0.2-汇总表.xlsx"
wb.save(out)
for ws in wb.worksheets: print(ws.title, ws.max_row, ws.max_column)
