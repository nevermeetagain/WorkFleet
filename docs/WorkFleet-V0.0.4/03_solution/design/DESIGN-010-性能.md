---
id: DESIGN-010
type: design
title: 性能详细设计（用户可感核心操作、预算与测量、SQLite 写入、令牌桶、批量、背压、场景推演）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - "REQ-NF-001"
  - "REQ-NF-002"
  - "REQ-NF-003"
  - "REQ-NF-011"
  - "REQ-F-033"
  - "ADR-003"
  - "ADR-005"
  - "ADR-009"
  - "DEC-013"
  - "DEC-017"
  - "DEC-023"
  - "DEC-040"
  - "DEC-046"
  - "packages/contracts/protocol/envelope.schema.json"
  - "packages/contracts/protocol/frames/welcome.schema.json"
  - "packages/contracts/adapters/channel-kinds.v1.json"
  - "V0.0.2/40-综合/08（场景推演、微信容量计算、S4 吞吐，部分确认）"
  - "V0.0.3/analysis-18-dimensions §10"
  - "05_execution/task-index.md（TASK-210）"
---

# DESIGN-010 性能

> **基线：尚无基线，首次测量见 TASK-210。** 下文所有预算是设计目标；来自需求的数值（REQ-NF-*）是验收线，其余为规划者分解的内部预算，首次测量后按实测修订本文。

## 1. 用户可感的核心操作
| # | 操作（用户感受） | 起点 → 终点 | 验收指标 | 为何与用户耗时直接相关 |
|---|---|---|---|---|
| O1 | 在 IM 发出一句话后多久看到“已收到/已转给” | 平台事件到达中转适配器 → 平台回执调用成功 / “已转给 [项目/别名]”回执发出 | p95 ≤ 3 s（渠道支持回执时，REQ-NF-001） | 用户发完消息盯着手机等回音；超过数秒会重发或怀疑掉线（飞书 3 秒回执亦为平台约束，DEC-017） |
| O2 | 在 Web 点发送后多久智能体开始处理 | `POST /messages` 到达中转 → 节点收到 `agent.prompt` 并入队 | p95 ≤ 1 s（同城）/ ≤ 2 s（跨境，部分确认）（REQ-NF-001） | 这是“我说的话送到电脑了”的时间；之后的耗时属于智能体本身，不归 WorkFleet |
| O3 | 智能体做完后多久在手机/网页看到结果 | 中转收到 `agent.output(final)` → 渠道 `send()` 被调用（Web：stream 推到浏览器） | p95 ≤ 500 ms（p0–p2，不含合并窗口与平台限速排队），Web p95 ≤ 300 ms（设计值） | 结果到达的延迟直接叠加在用户等待上；合并窗口是有意的产品行为，单独统计 |
| O4 | 点“批准”/回复 Y1 后多久智能体继续 | 审批入站（按钮回调或 Y1）到达中转 → 节点把 outcome 回给 ACP | p95 ≤ 1.5 s 同城 / ≤ 2.5 s 跨境（设计值） | 审批是阻塞点，智能体全程等待；慢审批 = 直接拖长任务 |
| O5 | 打开控制台多久能操作 | 导航开始 → 首屏可交互（TTI） | 4G 下 ≤ 3 s（REQ-NF-011） | Web 是默认渠道（DEC-057），首屏慢则用户转回 IM 或放弃 |
另有两条需求硬约束纳入同一测量体系：`/stop all` 在 5 s 内冻结全部智能体与出站（REQ-F-033）；单节点 ≥8 并发会话、空闲回收 15 分钟、控制面内存 ≤200 MB（REQ-NF-002）。

## 2. 预算分解
### O1（≤3 s）
| 段 | 预算 p95 | 手段 |
|---|---|---|
| 适配器解析 + `onInbound` 事务（recipient + message + token） | 50 ms | 单写者短事务；预编译语句 |
| 平台回执调用（`acknowledge`） | 由平台决定；中转侧发起 ≤100 ms | 回执在持久化后立即异步发出，不等路由 |
| 路由 + “已转给”系统消息入队 | 100 ms | 路由只读查询走读连接；delivery 唤醒信号 |
| 系统回执发送 | 渠道 RTT + 令牌桶等待 | 系统回执 priority=p1，绕过合并窗口 |
| 余量 | ≥2 s | 跨境 RTT 与平台抖动（香港 ↔ 平台连通性证据不足，U-04） |
### O2（≤1 s / ≤2 s）
| 段 | 预算 p95 |
|---|---|
| TLS 反代 + 中间件（DESIGN-002 §6） | 20 ms |
| 入站写库 + 路由 + `node_outbox` 写入 | 50 ms |
| WSS 发送（bufferedAmount < 1 MiB） | 10 ms |
| 网络单程（浏览器→中转 + 中转→节点） | 余量（同城 ≤500 ms，跨境 ≤1.5 s，均为推断） |
| 节点：去重 + 入队 | 20 ms |
### O3（≤500 ms）：帧校验 10 ms + 账本写入 20 ms + fanout 与过滤 50 ms + 渲染 20 ms + 令牌桶取令牌 0 ms（有余量时）+ 工作者唤醒 ≤50 ms。
### O4（≤1.5 s）：审批决策事务 30 ms + `approval.decision` 写 outbox 与发送 20 ms + 网络单程 + 节点回应 ACP 10 ms。
### O5（≤3 s）：首屏 JS ≤180 KB gzip、CSS ≤30 KB（DESIGN-001 §12.1）；`GET /me` 与首屏列表并行；静态资源长缓存 + 内容哈希；HTTP/2（由反代提供）。

## 3. 测量方法
| 指标 | 采集点 | 实现 |
|---|---|---|
| O1 | 中转：`InboundEvent.receivedAt`（适配器收到时刻）→ `acknowledge` 完成 / 回执 delivery `sent` | 直方图 `wf_inbound_ack_seconds{channel_kind}`、`wf_inbound_receipt_seconds{channel_kind}` |
| O2 | 中转在 envelope `sentAt` 写发送时刻；节点收到时以 `welcome.serverTime` 估算时钟偏差后计算 `recv - sentAt`，以及 HTTP 到达时刻（traceId 关联） | 节点直方图 `wf_prompt_delivery_seconds{link}`；中转 `wf_http_to_outbox_seconds` |
| O3 | 中转：帧到达 → `adapter.send()` 调用前 | `wf_output_to_send_seconds{channel_kind, priority}`（合并窗口内的单独记 `wf_merged_total`） |
| O4 | 中转：审批入站到达 → `approval.decision` 写 socket；节点：帧到达 → ACP 响应写出 | 两段直方图，traceId 拼接 |
| O5 | Playwright + Chrome DevTools 网络节流（4G 预设）测 TTI；Lighthouse CI（推断可用） | TASK-210 |
| /stop all | 中转 `emergency.stop` 发出 → 各节点 ack 且全部 agent.status=stopped | `wf_emergency_freeze_seconds` |
| 资源 | 节点控制面 RSS、子进程数；中转 RSS、SQLite 写事务耗时 | `process_resident_memory_bytes`、`wf_sqlite_tx_seconds{side,kind}` |
- 测试环境：E2E 中转实例端口 5110–5119（WF-ARCH §3）；FakeAgent/FakeChannel 去除外部不确定性；跨境数值另以真实香港中转 + 大陆节点测量并标注网络条件。
- 统计口径：每指标 ≥1000 样本取 p50/p95/p99；报告写入 `06_validation/`（TASK-210）。

## 4. SQLite 写入策略（ADR-003、ADR-009）
| 项 | 设定 | 理由 |
|---|---|---|
| 连接 | 1 个写连接（全进程共享，所有写经 `UnitOfWork`）+ 2–4 个只读连接（查询、FTS） | WAL 单写者；避免 `SQLITE_BUSY` 竞争 |
| PRAGMA | `journal_mode=WAL`、`synchronous=NORMAL`、`busy_timeout=5000`、`foreign_keys=ON`、`cache_size=-65536`（64 MiB，中转；节点 -16384）、`temp_store=MEMORY` | NORMAL 在 WAL 下仅掉电可能丢最后事务，配合至少一次投递可接受（推断） |
| 检查点 | `wal_autocheckpoint=1000`；RetentionSweeper 每小时 `PRAGMA wal_checkpoint(PASSIVE)`；关停 `TRUNCATE` | 控制 WAL 体积 |
| 事务 | `BEGIN IMMEDIATE`；单事务 ≤ 5 ms 目标；禁止在事务内做网络 IO | 同步 API 会阻塞事件循环（ADR-009 负面后果） |
| 批量 | fanout 插 deliveries ≤50 行/事务；ack 批量更新；审计在业务事务内同写 | DEC-013 |
| 长查询 | FTS 检索、审计大范围查询在 `worker_threads` 用独立只读连接 | ADR-009 |
| 语句 | 预编译并缓存（better-sqlite3 `prepare` 复用） | — |
| 监控与迁移触发 | `wf_sqlite_tx_seconds` p95 > 50 ms 持续 1 天、或库 > 20 GB、或需多实例 → 启动 ADR-003 方案 B（PostgreSQL） | ADR-003 |

## 5. 令牌桶（DEC-013）
```ts
class TokenBucket { constructor(public ratePerSec: number, public burst: number) {}
  tryTake(now: number): { ok: true } | { ok: false; waitMs: number } }
```
| 桶 | 键 | 速率来源 | 默认 |
|---|---|---|---|
| 渠道级 | `channel:<channelId>` | `capabilities.rateLimitPerSec` | 未声明时 1/s（保守，设计值） |
| 接收人级 | `recipient:<recipientId>` | 渠道能力或适配器常量 | 飞书 5/s（channel-kinds.v1；同用户/同群，V0.0.2/08 部分确认） |
| 租户级 | `tenant:<tenantId>` | 配置 `WF_TENANT_SEND_RATE` | 50/s（防单租户占满，设计值） |
| 入站防刷 | `inbound:<recipientId>` | 配置 | 30 条/分钟，超出回一次“发送过快”并丢弃后续（设计值） |
- 取不到令牌：`next_attempt_at = now + waitMs`，状态回 `queued`，**不计 attempts**。
- 平台 429：以 `retryAfterSec` 为准，并把对应桶清零到该时间点（自适应）。
- 微信额度预算（DEC-023）是独立的计数器（`channel_tokens.sent_since_refresh`），先于令牌桶检查；p0 保留 2 条额度（V0.0.2 §1.4 假设值，部分确认）。

## 6. 背压
| 环节 | 机制 | 阈值（设计值） |
|---|---|---|
| 中转 → 节点 WSS | 在途未 ack 窗口；超过则停止从 `node_outbox` 取新帧（帧已落库不丢） | 每设备 512 帧或 4 MiB；`ws.bufferedAmount > 1 MiB` 暂停写 |
| 节点 → 中转 WSS | 同上（`relay_outbox`） | 同上 |
| 节点执行面 | 每会话排队上限；全局 `maxSessions` 信号量 | 50/会话；8 会话 |
| 中转 delivery | 每轮取件 50；若某渠道 due 积压 > 10 000，p3 自动进入合并窗口、p2 延长合并 | 50；10 000 |
| Web stream | 每连接发送队列；溢出则丢弃并发 `resync`，前端以 REST 补齐（DESIGN-001 §6.3） | 1 000 事件 |
| 入站 | §5 入站防刷桶 | 30/分钟/接收人 |
| HTTP | 中间件 rate-limit（DESIGN-002 §6） | 600/分钟/IP |

## 7. 场景推演
### 7.1 场景 1：3 个项目 × 6 个工具同时开发，微信统一接收（S1/S2）
- 配置（V0.0.2/08 §1.1 形态）：1 台主力电脑，8 个智能体（Claude Code ×2、Codex ×2、Cursor、OpenClaw、ZCode、Coze），1 个微信 ClawBot 渠道 + 1 个备用渠道，管理模式。
- 节点资源：同时执行的会话 ≤8 = `maxSessions` 默认值，满足 REQ-NF-002 下限；第 9 个会话请求进入等待（空闲名额释放后启动），控制面内存主要来自 8 条 ACP peer 缓冲 + SQLite 缓存（16 MiB）+ 转录写入，预计远低于 200 MB（推断，TASK-210 实测）。子进程内存属于各智能体自身，不计入。
- 帧量：每个运行中会话约每 30 s 一条 status（DESIGN-003 §4.1）+ 每轮 1 条 final；8 会话 ≈ 16 帧/分钟级，SQLite 与 WSS 负载可忽略。
- 真正的瓶颈是**微信额度**（REQ-C-008，部分确认）：V0.0.2 §1.4 计算（假设参数）——逐条推送 61 条/天需 8 次入站/天，不可持续；按 DEC-017“审批/失败/阻塞逐条、完成按小时合并”约 25 条/天、4 次入站/天，可持续；审批回复本身是入站，会刷新额度。由此 delivery 必须实现合并窗口与额度预算（DESIGN-002 §7.1），p0 在额度为 0 时走备用渠道（REQ-F-030，60 s 内）。
- 时延：O1 主要取决于香港中转到 iLink 的往返（U-04 证据不足）；O2 跨境目标 ≤2 s。
### 7.2 场景 4：每天 9:00 向 ≤1 万订阅者推送（v2 功能，BL-002/003；本节验证 v1 结构能承载）
- 渠道：Telegram（公众订阅）、飞书/钉钉（公司内部）；**微信不参与**（DEC-046）。
- 写入：生成 1 条消息 + 1 万条 deliveries；按 50 行/事务 = 200 个事务；以单事务 ≤5 ms 目标计约 1 s 完成入队（推断，待实测）。
- 发送：吞吐由平台限速决定，不由 WorkFleet 决定。以 V0.0.2/08 的参数（部分确认）：Telegram 约 30 条/秒 → 10 000 ÷ 30 ≈ 333 s ≈ 5.6 分钟（V0.0.2 推演含开销记为 6.2 分钟）；飞书 50 条/秒 → 200 s ≈ 3.3 分钟（V0.0.2 记 3.7 分钟）。均满足 V0.0.2 设定的“1 万人 ≤10 分钟”目标。
- 中转负载：每发送 1 条 = 1 次 UPDATE（sending→sent），30–50 次/秒写入，远低于 SQLite 单写者能力（推断）；工作者每轮取 50，令牌桶控速，取不到令牌的回到 queued 不计次数。
- 平滑：08:55–09:05 分桶发送或按订阅者时区分桶（V0.0.2 设计），避免 9:00 整点 429；429 按 `retry_after` 自适应（§5）。
- 存储增长：1 万行/天 deliveries ≈ 365 万行/年；`rendered_payload` 90 天后清空（DESIGN-004 §2.7），行保留供审计。
- 风险：Telegram 付费广播门槛官方说法不一致（V0.0.2 部分确认）；飞书主动触达租户外用户（U-03）假设不能。

## 8. 与契约的差异 / 待办
| # | 发现 | 处理 |
|---|---|---|
| PF-1 | 渠道清单多数未给 `rateLimitPerSec`、`maxMessageChars` | 采用保守默认（1/s、2000 字，设计值），各渠道 TASK 实测回写契约 |
| PF-2 | envelope `sentAt` 使用发送方时钟，跨机计算延迟需时钟偏差估计 | 用 `welcome.serverTime` 估算；精度不足时只报告同机分段耗时 |
| PF-3 | 基线指标文件 `04_planning/baseline-metrics.md`（REQ-NF 文件引用）不存在 | 由 TASK-210 首次测量后创建 |
