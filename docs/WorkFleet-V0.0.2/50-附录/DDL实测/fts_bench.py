import sqlite3, time, random, statistics
db=sqlite3.connect("/tmp/gw_bench.db"); db.executescript(open("../../40-综合/05-gateway-schema-v002.sql",encoding="utf-8").read())
words=["登录","超时","修复","测试","通过","深色","主题","数据库","迁移","接口","审批","微信","飞书","总控","会议","派工","回归","部署","端口","订阅"]
N=200000
t=time.time()
db.execute("BEGIN")
for i in range(N):
    txt="".join(random.choice(words) for _ in range(12))+f" #{i}"
    db.execute("INSERT INTO event(id,dir,kind,src,text_digest,ts) VALUES(?,?,?,?,?,?)",(f"E{i:08d}","out","msg.final","acp:x",txt,"2026-10-17T00:00:00Z"))
db.execute("COMMIT")
ins=time.time()-t
lat=[]
for q in ["登录超时","深色主题","数据库迁移","总控会议","审批微信","端口部署"]*5:
    s=time.perf_counter(); db.execute("SELECT count(*) FROM event_fts WHERE event_fts MATCH ?",(q,)).fetchone(); lat.append((time.perf_counter()-s)*1000)
import os
lat.sort()
print(f"N={N} 单事务批量写入 {ins:.1f}s（{N/ins:.0f} 行/秒，含 FTS 触发器）")
print(f"FTS count 查询 30 次：p50={statistics.median(lat):.1f}ms p95={lat[int(len(lat)*0.95)-1]:.1f}ms max={lat[-1]:.1f}ms")
print(f"db 文件 {os.path.getsize('/tmp/gw_bench.db')/1e6:.1f} MB（WAL 另计）")
