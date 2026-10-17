---
id: DESIGN-015
type: design
title: 资源（并发上限、空闲回收、子进程观测、进程树管理、文件句柄、连接数、中转主机规格）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - DEC-002/003/013/021/041/051
  - ADR-003、ADR-005、ADR-009
  - REQ-NF-002/003/006、REQ-F-001/032/033
  - architecture §3/§4.2
  - database/migrations/node/0001_init.sql（prompt_queue、sessions、write_leases）
  - packages/contracts/api/node-local.openapi.json（GET /local/v1/status 资源占用）
  - V0.0.2/30-协议与端点/01 §3/§12、03 §0/§2/§5、04 §3.2
  - V0.0.3/03_solution/analysis-18-dimensions.md §15
---

# DESIGN-015：资源

> 证据标签：已确认 / 部分确认 / 证据不足 / 推断 / 待实测。单智能体常驻内存与冷启动时间在 V0.0.2 中为**证据不足**，本文所有阈值都是“默认值 + 实测回填”。

## 1. 进程模型回顾
- 节点 = 单进程控制面 + **每个智能体会话一个子进程**（architecture §3/§4.2、DEC-002）。
- 一个“会话”= relay 的 `conversationId` 的当前 `generation`；子进程内只开一个 ACP session（ACP 允许一个连接多 session，V0.0.2/01 C3；v1 不复用，换取故障隔离与按会话回收，推断）。
- 每会话同时最多 **1 个进行中轮次**（`prompt_queue` 按 conversation 串行；同会话并发会交错写转录，V0.0.2/04 §3.2）。

## 2. 并发上限（节点）
| 参数（`kv_settings` 键，可在本机控制台改） | 默认 | 硬上限 | 依据 |
|---|---|---|---|
| `resources.maxLiveSessions`（存活子进程总数） | 12 | 32 | REQ-NF-002 要求 ≥8 并发；V0.0.2/04 建议全局 16（证据不足），取保守 12 |
| `resources.maxRunningTurns`（全局同时执行的轮次） | 8 | 32 | REQ-NF-002 ≥8 |
| `resources.maxRunningTurnsPerAgent`（同一智能体实例跨会话） | 4 | 8 | V0.0.2/04 “每 Profile 4” |
| `resources.maxConcurrentSpawns`（同时冷启动中的子进程） | 2 | 4 | OR“每 tick 最多新建 1 终端”（analysis §15），防 CPU 尖峰 |
| `resources.maxQueuedPromptsPerConversation` | 20 | 100 | 推断；超出拒绝新 prompt（`RATE_LIMITED`，retryAfterSec=30） |
| 总控 LLM 并发调用 | 2 | 4 | DESIGN-020 §8 |

### 2.1 调度算法（`agents` 模块 `Scheduler`）
```text
loop on (prompt enqueued | turn finished | process exited | timer 1 s):
  for conv in conversations with queued prompts, ordered by (priority asc, enqueued_at asc):   # p0 优先
    if conv has running turn: continue
    if running_turns >= maxRunningTurns or running_turns_of(conv.agent) >= maxRunningTurnsPerAgent: continue
    if conv 无存活进程:
        if live_sessions >= maxLiveSessions: evictLRUIdle() or continue      # 只驱逐 idle 会话
        if spawning >= maxConcurrentSpawns: continue
        spawn(conv)  → 冷启动完成后再次进入循环
    else start turn
```
- 排队反馈：入队时若位次 > 1，节点回 `agent.status{queueDepth}`，中转回执显示“已排队（第 N 位）”（DESIGN-013 §2.2）。
- 写租约（G10）：`writeMode=write` 的智能体开始轮次前须持有 `write_leases`（DESIGN-003）；冲突 → `AGENT_BUSY_WRITE_LEASE`，不占用调度槽。

## 3. 空闲回收（REQ-NF-002：空闲会话 15 分钟回收）
| 状态 | 判定 | 动作 |
|---|---|---|
| 会话 idle | 无进行中轮次、无待答权限，`last_active_at` 距今 ≥ **15 min** | 若支持 `session/close` 先调用（超时 5 s）→ 优雅结束子进程（§4）→ `sessions.state='idle'`（保留 `native_session_id`） |
| 下次 prompt | 会话无进程 | spawn → `initialize` → 若 `supportsLoadSession` 且有 `nativeSessionId`：`session/resume`（不回放，优先）或 `session/load`（回放）→ 否则 `session/new` 并在转录写 `system: 上下文已重置`，同时在回复中提示一次（V0.0.2/01 §6） |
| 待答权限中 | 不回收 | 审批超时（DESIGN-018）后才计 idle |
| LRU 驱逐 | 达到 `maxLiveSessions` 且有新会话需启动 | 驱逐最久 idle（≥ 60 s）的会话，同上流程 |
- 回收前 `agent.status` 上报 `idle`；中转不感知进程存在与否（只感知会话状态）。

## 4. 进程树管理

### 4.1 启动（三平台共同）
- `child_process.spawn(cmd, args, { cwd: workdir, env: sanitizedEnv, stdio: ['pipe','pipe','pipe'], windowsHide: true })`。
- `sanitizedEnv`：继承用户环境（外部工具要用其自身登录态，DEC-044），**移除** `WF_*` 内部变量与 WorkFleet 自身密钥；加入 spec `launch.env`（input-adapter-spec.schema.json）。
- stdout 只接受 NDJSON：首行非 JSON → 隔离该智能体（`AGENT_UNAVAILABLE`，诊断写 stderr 片段，V0.0.2/01 §3）；单行上限 **16 MiB**（V0.0.2/01 建议 16–32 MiB），超限关闭会话并 p1 告警。
- stderr：环形缓冲 64 KiB（诊断用），按行写节点日志（级别 debug，带 traceId）。

### 4.2 Windows
- `.cmd`/`.bat` 启动（如 npm 全局 shim）：自 2024-04 起 Node 安全修复禁止不带 `shell` 直接 spawn `.cmd/.bat`（CVE-2024-27980，部分确认：Node 18.20.2/20.12.2 发布说明）→ 使用 spec 的 `windowsCommand`（优先指向真实 `.exe`/`node.exe + js`）；只能 `.cmd` 时以 `cmd.exe /d /s /c` 包装，参数严格转义（禁止拼接用户输入）。
- **Job Object**（DEC-021、G12）：每个子进程放入独立 Job，设置 `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`，节点崩溃时 OS 自动结束整棵进程树；可选 `JOB_OBJECT_LIMIT_JOB_MEMORY`（默认不设，见 §5）。
  - 实现：Node 无内置 API → 方案 A：随安装包分发的小型原生 helper（`wf-jobrun.exe <job-name> -- cmd…`，创建 Job 后 `CreateProcess` 挂起→加入 Job→恢复）；方案 B：N-API 原生模块。选择与许可在 TASK 中定（证据不足）。
  - 兜底：`taskkill /PID <pid> /T /F`。
- 结束顺序：先 ACP `session/cancel`（若有轮次）→ 关闭 stdin → 等 5 s → 关闭 Job（终止整树）。Windows 无 SIGINT 等价的可靠跨进程信号（推断），故依赖 stdin 关闭 + Job。

### 4.3 macOS / Linux（POSIX 进程组）
- `spawn(..., { detached: true })` → 子进程成为新进程组组长（PGID = PID）。
- 结束顺序：`session/cancel` → `process.kill(-pgid, 'SIGINT')` → 5 s → `SIGTERM` → 5 s → `SIGKILL`。SIGINT 优先：Claude 相关文档称 SIGTERM 会丢本轮结果（V0.0.2/04 §3.2，部分确认）。
- 孤儿回收：节点崩溃时 detached 子进程不会自动退出 → 每次 spawn 把 `{pid, pgid, conversationId, startedAt}` 写 `run/pids.json`（原子重写）；节点启动时读该文件，对仍存活且启动时间吻合的 PGID 发送 SIGTERM→SIGKILL（防 PID 复用：比对 `/proc/<pid>/stat` starttime 或 `ps -o lstart`，待实测）。Windows 由 Job 自动处理，同样登记以便诊断。
- Linux 自启：systemd user unit（`KillMode=control-group` 让 systemd 停服务时清理整组）；macOS：launchd LaunchAgent（DEC-041）。

## 5. 子进程内存 / CPU 观测
- 采样：每 **10 s** 对每个子进程树采样 RSS 与 CPU%：
  - Linux：读 `/proc/<pid>/stat`、`/proc/<pid>/status`（VmRSS），遍历进程组；
  - macOS：`ps -o pid,pgid,rss,%cpu -g <pgid>`（每 10 s 一次 fork，开销可接受，推断）；
  - Windows：Job Object 查询 `JobObjectBasicAccountingInformation`/`ExtendedLimitInformation`（PeakJobMemoryUsed）经 helper 暴露（待实测）；兜底 `tasklist`/PowerShell `Get-Process`（慢，降到 60 s）。
- 阈值（默认，待实测回填）：

| 级别 | 条件 | 动作 |
|---|---|---|
| warn | 单会话树 RSS ≥ 1.5 GiB 持续 60 s | p2 通知 + 本机控制台标黄 |
| hard | 单会话树 RSS ≥ 3 GiB 或节点所在机器可用内存 < 10% | 当前轮次结束后回收该会话（不中断执行中轮次）；若持续 5 min 仍超 → `session/cancel` + 结束进程 + p1 |
| cpu | 单会话 CPU ≥ 90%（单核）持续 10 min 且无任何 session/update | 判定疑似卡死 → p1“疑似卡住”，提示 `/stop`；不自动杀 |
- 上报：`GET /local/v1/status` 返回 `resources: {sessions:[{conversationId, pid, rssBytes, cpuPct, startedAt}], totals:{rssBytes}}`（契约响应为未约束 object，差异 #1）；`/metrics`（5104）：`wf_node_child_rss_bytes{agent}`、`wf_node_child_cpu_pct{agent}`、`wf_node_live_sessions`、`wf_node_running_turns`、`wf_node_spawn_duration_ms`。

### 5.1 控制面自身（REQ-NF-002：≤ 200 MB，不含子进程）
| 消耗源 | 约束 |
|---|---|
| better-sqlite3 页缓存 | `PRAGMA cache_size=-16384`（16 MiB/连接），≤ 2 连接（主 + FTS worker） |
| 轮次聚合缓冲 | 每轮 `finalText` ≤ 4 MiB（DESIGN-013 §6）；超出转附件 |
| stderr 环形缓冲 | 64 KiB × 会话数 |
| relay_outbox 内存窗口 | 只在内存保留未 ack 帧的 seq 与大小，正文在库 |
| 总控上下文 | 每次 LLM 请求组装后释放；摘要缓存 LRU ≤ 500 条 |
测量：`process.memoryUsage().rss` 每 60 s 记录；持续 > 200 MB 记 p2 并输出 heap 统计（v8.getHeapStatistics）。

## 6. 文件句柄
| 位置 | 句柄 | 约束 |
|---|---|---|
| 节点每会话 | 3 管道 + 1 转录追加句柄 | 会话 idle 回收时关闭转录句柄 |
| 节点 SQLite | db + wal + shm × 2 连接 | — |
| 节点合计（12 会话） | ≈ 80 | Windows 无 ulimit 问题；macOS 默认软限 256 足够（推断） |
| 中转 | 每 WSS/HTTP 连接 1 socket；附件流式传输期间 1 文件 | systemd `LimitNOFILE=65536`；启动时若 `ulimit -n` < 4096 打 WARN（doctor 同检查） |

## 7. 连接数
| 连接 | 数量模型 | 依据 |
|---|---|---|
| 节点 → 中转 WSS | 每条 relay link 1 条（DEC-048 多中转则 N 条）；同一设备重复连接时中转**踢掉旧连接**（close 4001，DESIGN-016） | ADR-005 |
| 浏览器 → 中转 `/api/v1/stream` | 每个标签页 1 条；每会话（Web session）上限 5，超出关闭最旧 | 推断 |
| 中转 → 飞书长连接 | 每渠道（应用）1 条；平台每应用 ≤ 50 条，且为集群模式（多连接只有一个收到） | 已确认 V0.0.2/03 §2 |
| 中转 → 钉钉 Stream | 每渠道 1 条 | 已确认 |
| 中转 → QQ WebSocket | 每渠道 1 条 | 已确认 |
| 中转 → Discord Gateway | 每 Bot 1 条；> 2,500 服务器需分片（v1 不支持分片，超出告警） | 已确认 |
| 中转 → Telegram getUpdates | 每 Bot 1 个在途长轮询 HTTP 请求 | 已确认（与 webhook 互斥） |
| 中转 → 微信 iLink getupdates | 每渠道 1 个在途长轮询（~35 s） | 已确认 |
| 中转 → Web Push 服务 | 按需短连接（HTTP keep-alive 复用） | — |
- 中转 WSS 背压与帧窗口见 DESIGN-016 §6。
- 每个 tenant 设备数上限默认 20、渠道数上限 20（推断，防滥用；超出 `RATE_LIMITED`）。

## 8. 中转资源与主机规格建议
### 8.1 中转内部限额
| 参数 | 默认 | 依据 |
|---|---|---|
| delivery worker 并发 | 每渠道 4 个在途发送 | DEC-013 令牌桶 + 批 ≤50 |
| 令牌桶 | 飞书单用户/单群 5 QPS（已确认）；Telegram 单聊 1/s、群 20/min、全局 30/s（已确认）；Discord 读响应头；QQ/钉钉按 V0.0.2/04 §6 预设 | V0.0.2/03 |
| node_outbox 单设备未 ack 上限 | 10,000 帧 | 超出：新 `agent.prompt` 拒绝（`DEVICE_OFFLINE` 已排队满，retryable）；p1 |
| 每设备帧接收速率 | 200 帧/s（超出暂停读取，TCP 背压） | 推断 |
| HTTP 请求体 | JSON ≤ 1 MiB；附件 ≤ 25 MiB | resources.json、ADR-005 |

### 8.2 主机规格（推断，部署前以压测回填）
| 场景 | vCPU | 内存 | 磁盘 | 带宽 | 理由 |
|---|---|---|---|---|---|
| 个人 / 两人共用（DEC-039） | 1 | 1 GiB（建议 2 GiB） | 20 GiB SSD | 1–3 Mbps | 单 Node 进程常驻（推断 150–300 MiB）+ SQLite；IM 长连接 ≤ 10 条 |
| 公司自建（≤ 数百用户，ADR-003 推断量级） | 2 | 4 GiB | 100 GiB SSD（按 DESIGN-014 §8：约 40 GiB/年消息 + 附件 90 天） | 10 Mbps | 单进程单写者 → CPU 主要在 TLS（由 Caddy/Nginx 承担）与 JSON 校验；第二核留给反代与备份压缩 |
| 迁移信号 | — | — | — | — | ADR-003：写入 p95 > 50 ms 持续 1 天 / 单库 > 20 GB / 需要多实例 |
- 选址：香港（DEC-040）；跨境 RTT 与 iLink 连通性**证据不足**（U-04），TASK-041 记录。
- 压测计划（TASK 级）：FakeChannel 200 msg/s 入站 + 50 个 FakeNode 设备，测 p95 写入延迟、RSS、CPU，回填本表。

## 9. 与契约的差异 / 待办
1. `GET /local/v1/status` 响应为未约束 object → 建议定义 `resources` 子结构（§5）。
2. 资源参数（maxLiveSessions 等）无节点配置契约（node-local 无 settings 端点）→ 建议 `GET/PUT /local/v1/settings`。
3. node `sessions` 无 pid 列（孤儿回收用 `run/pids.json`，DESIGN-014 差异 #5）。
4. Job Object helper / N-API 方案的实现与许可证据不足，需 TASK 实测后补 ADR。
