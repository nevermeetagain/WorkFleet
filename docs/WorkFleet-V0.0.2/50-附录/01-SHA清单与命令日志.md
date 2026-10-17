# 50-附录 · 01 SHA 清单与命令日志（V0.0.2 综合轮）

> 记录时间：2026-10-17 09:49–约 11:30 CST（Asia/Shanghai）。所有命令在 Hark 沙箱（Linux，Python 3.12.15，SQLite 3.46.1）执行。

## 1. SHA 清单（本轮最终口径）

| 对象 | SHA / 版本 | 获取 | 用于 |
|---|---|---|---|
| WechatClawbot | `4ec3bbe8` | `10-参考项目/11` | 参考 |
| Paperclip | `0528cc7e` | `10-参考项目/12` | 参考 |
| PentAGI | `843dfeb` | `10-参考项目/13` | 参考 |
| Orca | `fd1c6a5`（1.4.214） | `10-参考项目/14` | 参考 |
| Hindsight | `5331da2`（v1.0.0） | `10-参考项目/15` | 参考 |
| BettaFish | `b67928f` | `10-参考项目/16` | 参考 |
| cc-connect | `2dec7173bdd44ec598c3c7e5c7ff00407acfdedf` | `git ls-remote` | 入围 |
| OpenClaw | `acd27635ccdc31f7970907524531f101c2d48fd1` | `git ls-remote` | 入围 |
| AionUi / AionCore | `c140550d…` / `503a8719…`（无新提交） | `git ls-remote` | 入围 |
| AstrBot | `de898afe7588e1f153beec06e24f03f6ddeae2e4` | `git ls-remote` | 入围 |
| acpx | `0d874f9a98de2a82ed8c5a4746053bd0a46052c3`（v0.19.6） | `git ls-remote` + releases | 入围 |
| ACP 规范 | `e7dac67ac64ec7cf69079b3bb6eff46a21e026b3`（v1.12.0 / schema-v1.26.0 / schema-v2.0.0-alpha.9） | ls-remote + releases | 协议 |
| claude-agent-acp | `dbf386d8d35d2bc30f17f11f15d1a4305c9d391f`（v0.93.0） | ls-remote + releases | 适配器 |
| codex-acp | `59974c7d173e4fd6ef9498fc1e91779606c2404d`（v2.2.2） | ls-remote + releases | 适配器 |
| ACP python-sdk | `bdb9ac7054fb2df76a922b60b356c3c65f8a8a64`；PyPI 0.12.1（稳定）/ 1.0.0rc3 | ls-remote + PyPI | SDK |
| ZCode | `aac4755666d09fdcd70272fcf063c077a639015f`（package.json 3.15.1；Release 对象 v3.14.3；Apache-2.0） | ls-remote + API + raw | 输入端 |
| holiday-cn | master（2027.json 为空） | raw | 调度 |

## 2. 命令日志

| # | 命令（摘要） | 结果摘要 | 证据文件 |
|---|---|---|---|
| C1 | `cp -r _V0.0.1基线/{20-同类开源,30-协议与端点} V0.0.2/` | 复制完成 | 目录 |
| C2 | `git ls-remote https://github.com/<repo> HEAD` × 11 | 全部成功（见 §1） | `20-同类开源/refs-commits-V0.0.2.md` |
| C3 | `curl api.github.com/repos/<repo>` × 11 | stars/license/pushed_at | 同上 |
| C4 | `curl api.github.com/repos/<repo>/releases?per_page=3` × 9 | claude-agent-acp v0.93.0；codex-acp v2.2.2；ACP v1.12.0；acpx v0.19.6；python-sdk 1.0.0rc3；ZCode v3.14.3 | 同上 |
| C5 | `curl api.github.com/repos/chenhg5/cc-connect/contents/` | 无 LICENSE 文件 | 同上 |
| C6 | `curl …/compare/<old>...<new>` × 6 | 新增提交与变更文件 | 同上 |
| C7 | OpenClaw 关键文件 md5（旧/新 SHA） | `resolve-route.ts`、`cron/types.ts`、`broadcast-groups.md`、`wechat.md` 一致；extensions 无 dingtalk | `40-综合/01 §0` |
| C8 | `curl raw…/zai-org/ZCode/main/{README.md,LICENSE,package.json}`；`grep -i acp` | README 无 acp；Apache-2.0；3.15.1 | refs-commits |
| C9 | `curl pypi.org/pypi/agent-client-protocol/json` | 0.12.1 最新稳定；rc1–rc3 | refs-commits |
| C11 | `pytest tests/e2e/test_walking_skeleton.py tests/rel/test_watchdog.py` | 失败断言：`blocked==1`；“watchdog 未能在时限内自动拉起新进程” | 同上 |
| C12 | `pip install agent-client-protocol==0.12.1`；`dir(acp.ClientSideConnection)`、`dir(acp.Client)` | API 面见 `05 §4.1` | `40-综合/05` |
| C13 | `python3 compute.py`（评分）/ `options.py`（方案）/ `wechat_capacity.py`（额度） | 见 `40-综合/01`、`04 §4.7`、`08 §1.4` | `50-附录/评分底稿/` |
| C14 | `sqlite3 /tmp/gw.db < 40-综合/05-gateway-schema-v002.sql`；`< ddl_test.sql` | 57 表/67 索引/3 触发器；15 用例全部符合期望 | `50-附录/DDL实测/ddl_test_output.txt` |
| C15 | `sqlite3 :memory: < v001_fts_defect.sql` | V0.0.1 DDL FTS 命中 0（缺陷复现） | `v001_fts_defect_output.txt` |
| C16 | `python3 fts_bench.py` | 20 万合成：写入 15.4k 行/秒；count p95 1.7ms | `fts_bench_output.txt` |
| C17 | `curl raw…/holiday-cn/master/{2026,2027}.json` | 2026 调休上班 6 天；2027 `days: []` | `40-综合/07 §0` |
| C18 | `python3 build_xlsx.py` | 8 个工作表 | `40-综合/WorkFleet-V0.0.2-汇总表.xlsx` |

## 3. 未执行 / 失败
- 未对任何候选项目做运行时测试（按任务“不重做深度分析”）。
- OpenClaw +894 提交只核对了被引用文件 md5 与 extensions 目录，未全量审读（PoC-12）。
- 未复抓各 IM 官方限额页（`30-协议与端点/03` 标注【V0.0.2更新】）。
