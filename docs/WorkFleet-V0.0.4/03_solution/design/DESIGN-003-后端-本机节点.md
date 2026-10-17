---
id: DESIGN-003
type: design
title: 后端详细设计 · 本机节点（apps/node）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - "WF-ARCH §3/§4.2/§6/§7"
  - "ADR-005"
  - "ADR-007"
  - "ADR-009"
  - "ADR-013"
  - "DEC-002"
  - "DEC-003"
  - "DEC-007"
  - "DEC-012"
  - "DEC-017"
  - "DEC-020"
  - "DEC-021"
  - "DEC-022"
  - "DEC-037"
  - "DEC-041"
  - "DEC-044"
  - "DEC-048"
  - "DEC-049"
  - "DEC-055"
  - "REQ-F-001/006/007/008/019/020/026/029/032/033/035"
  - "REQ-NF-002/003/004/006"
  - "packages/contracts/protocol/**"
  - "packages/contracts/adapters/**"
  - "packages/contracts/api/node-local.openapi.json"
  - "database/migrations/node/0001_init.sql"
  - "V0.0.2/10-参考项目/14（Orca：peer 上限、launch-spec、dialect、held、单实例锁、supervise）"
---

# DESIGN-003 后端 · 本机节点

## 1. 范围
本机节点在 Windows 10+/macOS 13+/主流 Linux 上常驻（Node 22 LTS），**拉起并驱动智能体**、连接 1..N 个中转、运行总控与会议、保存模型配置（Key 在 OS 钥匙串）与分身数据。所有端口只绑 127.0.0.1（5100 本机控制台/API、5102 Webhook、5103 MCP、5104 metrics；DEC-051、REQ-NF-004）。代码与工作目录内容不出本机（DEC-037）。

## 2. 进程模型
```text
workfleet-node run [--supervise]
 ├─ (可选) 监督进程：仅负责重启控制面；6 次失败/15 分钟 → 放弃并写日志（借鉴 Orca serve --supervise 语义，DEC-021）
 └─ 控制面进程（单进程，单实例锁 §8）
     ├─ HTTP 127.0.0.1:5100  local-console（node-local API + apps/web node 目标静态资源）
     ├─ HTTP 127.0.0.1:5102  Webhook 输入（/hooks/{hookId}）
     ├─ HTTP 127.0.0.1:5103  MCP（智能体主动推送工具，DEC-022；v1 只实现 send_message，见 §10.6）
     ├─ HTTP 127.0.0.1:5104  /metrics
     ├─ RelayLink × N（每个中转一条出站 WSS，§9）
     ├─ AcpHost：会话调度器 + 每会话一个执行面子进程（§4–§6）
     ├─ Supervisor / Meetings（总控，DESIGN-020）
     └─ worker_threads：transcript FTS 写入与检索（ADR-009：长查询放 worker）
 执行面子进程（每个智能体会话 = 一个 OS 进程树）
     stdin/stdout：ACP JSON-RPC（NDJSON）；stderr：诊断日志（按平台解码，§6.4）
```
| 资源约束 | 值 | 依据 |
|---|---|---|
| 并发执行会话上限 `maxSessions` | 默认 8（可配，≥8 为验收下限） | REQ-NF-002 |
| 空闲回收 | 15 分钟（受 `supportsLoadSession` 约束，§5.4） | REQ-NF-002、DEC-021 |
| 控制面常驻内存 | ≤ 200 MB（不含子进程） | REQ-NF-002 |
| ACP 单行上限 / 写队列 | 16 MiB / 32 MiB；并发请求 128 | 借鉴 Orca `acp-peer-limits`（V0.0.2/14 已确认），设计值 |

## 3. 目录树（文件级）
```text
apps/node/src/
├── bootstrap/{main.ts（CLI：run|pair|autostart|doctor|recovery）, container.ts, http.ts, shutdown.ts, supervise.ts}
├── core/
│   ├── config/{schema.ts, load.ts, paths.ts（三平台数据目录）}
│   ├── db/{connection.ts, migrate.ts, kysely-types.ts}                 # Agent-Data
│   ├── logging/{logger.ts, redact.ts（Key/令牌脱敏）}
│   ├── errors/app-error.ts
│   ├── security/{keychain/{index.ts, dpapi.ts, macos-keychain.ts, libsecret.ts, encrypted-file.ts}, local-token.ts, hmac.ts}
│   ├── platform/{instance-lock.ts, process-tree/{index.ts, windows-job.ts, posix-pgid.ts}, autostart/{windows.ts, macos.ts, linux.ts}, decode.ts}
│   └── metrics/registry.ts
├── shared/{domain/{ids.ts, clock.ts, result.ts}, application/{event-bus.ts, wake-signal.ts, semaphore.ts}}
└── modules/
    ├── relay-link/
    │   ├── domain/{relay-link.ts, seq-window.ts, backoff.ts}
    │   ├── application/{add-link.ts（url+配对码→claim→令牌入钥匙串）, remove-link.ts, connection.ts（握手/续传/心跳）, dispatch.ts（帧→模块）, send.ts}
    │   ├── interfaces/http/routes.ts                       # /local/v1/relay-links*
    │   ├── infrastructure/{ws-client.ts, link-repo.sqlite.ts, outbox-repo.sqlite.ts, dedupe-repo.sqlite.ts}
    │   └── index.ts                                        # sendToRelay(linkId, type, payload)
    ├── agents/
    │   ├── domain/{agent.ts, host-state.ts（§4 状态机）, adapter-spec.ts}
    │   ├── application/{host.ts（AcpHost 调度）, start-session.ts, prompt.ts, cancel.ts, permission-bridge.ts（ACP 权限→approval.request）,
    │   │               detect.ts, namespace/guard.ts（按 relay_link_id 隔离）, echo/（S0 FakeAgent 回声）, aggregate.ts（流式→状态卡/最终消息）}
    │   ├── interfaces/{gateway/on-frames.ts（agent.prompt/cancel/clear、approval.decision、emergency.*）, http/routes.ts（/local/v1/adapters/detect）}
    │   ├── infrastructure/
    │   │   ├── acp/{peer.ts（JSON-RPC NDJSON，上限与超时）, client.ts（initialize/session.*）, launcher.ts}
    │   │   ├── dialects/{index.ts, zcode/}                 # AcpDialect 实现（DESIGN-007 §3）
    │   │   ├── specs/{index.ts（载入 input-adapters.v1.json + 本地覆盖）, group-a/, group-b/, openclaw/}
    │   │   ├── coze/{adapter.ts}                          # family=coze_http
    │   │   └── webhook/{server.ts（5102）, verify.ts}       # family=webhook
    │   └── index.ts
    ├── sessions/
    │   ├── domain/{session.ts（conversationId+generation）, transcript-line.ts}
    │   ├── application/{open.ts, clear.ts（generation+1）, resume.ts, query-history.ts（history.query→history.result）, queue.ts（§5）}
    │   ├── infrastructure/{session-repo.sqlite.ts, transcript-writer.ts（JSONL 追加 + transcript_index）, queue-repo.sqlite.ts}
    │   └── index.ts
    ├── workspace-guard/{domain/lease.ts, application/{acquire.ts, release.ts, worktree.ts, heartbeat.ts}, infrastructure/lease-repo.sqlite.ts, index.ts}
    ├── models/{domain/{profile.ts, budget.ts}, application/{crud.ts, test-profile.ts, record-usage.ts, check-budget.ts},
    │           infrastructure/{profile-repo.sqlite.ts, usage-repo.sqlite.ts, providers/{openai-compatible.ts, anthropic.ts}}, interfaces/http/routes.ts, index.ts}
    ├── supervisor/{domain/{verdict.ts, rules.ts}, application/{judge.ts, chat/, dispatch/, import/}, interfaces/http/routes.ts, infrastructure/*.sqlite.ts, index.ts}
    ├── meetings/{domain/{meeting.ts, round.ts}, application/{open.ts, run-round.ts, summarize.ts, decide.ts}, infrastructure/*.sqlite.ts, index.ts}
    ├── twin/{domain/twin-event.ts, application/{capture.ts, list.ts, edit.ts, delete.ts, export-jsonl.ts}, interfaces/http/routes.ts, infrastructure/twin-repo.sqlite.ts, index.ts}
    ├── local-console/{interfaces/http/{static.ts, auth.ts（本机令牌 Cookie）}, index.ts}
    └── system/{application/{doctor/, emergency/{freeze.ts, resume.ts}, recovery/{export.ts, import.ts}, status.ts}, interfaces/http/routes.ts, index.ts}
```

## 4. ACP Host 状态机（每会话一个实例）
```text
            spawn ok          initialize ok            session/new|load ok
 [absent] ──────────▶ [spawning] ─────▶ [initializing] ─────────────────▶ [idle]
    ▲   spawn 失败(ENOENT/EACCES)            │ 失败/超时 30 s                │ prompt 出队
    │   └──────────▶ [unavailable] ◀─────────┘                              ▼
    │                (AGENT_UNAVAILABLE；doctor 提示)                    [running] ──end_turn/max_tokens/refusal──▶ [idle]
    │                                                                     │  ▲
    │                                     session/request_permission      │  │ approval.decision → 回应 ACP
    │                                                                     ▼  │
    │                                                            [waiting_approval]
    │                                                                     │
    │   /stop 或 急停：发 session/cancel ──▶ [cancelling] ──stopReason=cancelled 或 10 s 超时──▶ [idle]（超时则杀进程树 → [absent]）
    │
    ├── 空闲回收（§5.4）/ 设备关停：close → kill 进程树 ──▶ [absent]
    └── 子进程异常退出（任何状态）──▶ [crashed] ─ 退避 1 s/5 s/30 s，15 分钟内 ≥3 次 ─▶ [error]（status=error，需 /clear 或控制台重启）
```
- 对外状态映射到契约 `agent.status` 枚举：absent/idle → `idle`；spawning/initializing/running/cancelling → `running`；waiting_approval → `waiting_approval`；unavailable → `unavailable`；crashed/error → `error`；急停冻结 → `stopped`。状态变化发 `agent.status{agentId,status,queueDepth}`（节流：同一 agent 每秒最多 1 帧）。
- ACP 调用序列（方法名以 ACP v1 规范为准，TASK-021 用官方 SDK 生成类型校对，U-05）：
```text
initialize { protocolVersion: 1, clientCapabilities: { fs: {readTextFile:false, writeTextFile:false}, terminal: false } }
   # 设计选择：节点不代智能体读写文件，智能体用自身工具；若某智能体必须客户端 fs 能力，在其 spec.dialect 中声明（待实测）
session/new  { cwd: <workdir 或 worktree>, mcpServers: [<可选 WorkFleet MCP 127.0.0.1:5103>] }
   或 session/load { sessionId: nativeSessionId, cwd, mcpServers }（仅 spec.supportsLoadSession=true）
session/prompt { sessionId, prompt: [{type:'text', text}] }  → 流式 session/update 通知 → 返回 { stopReason }
session/cancel（通知）
智能体 → 客户端：session/request_permission { sessionId, toolCall, options[] } → 回 { outcome: {outcome:'selected', optionId} | {outcome:'cancelled'} }
```
- `stopReason` → `agent.output.kind`：`end_turn` → `final`；`max_tokens`/`refusal` → `final`（正文前加 callout(warn)）；`cancelled` → `status`（“已停止”）；JSON-RPC 错误/进程退出 → `error`。

### 4.1 流式聚合（DEC-017）
- `session/update` 的文本块写入转录 JSONL（全部保留，在本机）；**不逐块回传**。
- 回传规则：①轮次开始后 3 s 若未结束，发一条 `agent.output{kind:'status', body: status_card(running, title, progress?)}`；②之后每 30 s 至多一条 status（渠道可编辑时由中转编辑同一张卡，见 §11 N-2）；③结束发 `final`（正文 = 最后一个 agent 消息的完整文本，转 IR：markdown 段落/代码块拆分，DESIGN-007 §4）；④失败/阻塞发 `error`，`priority=p1`；审批发 `approval.request`，`priority=p0`。
- 总控模式下所有 `final/error` 先交 `supervisor.judge()`，带 `supervisorVerdict` 再回传（DEC-018，DESIGN-006 §4.4）。

### 4.2 权限请求 → 审批（REQ-F-020）
```text
on session/request_permission(req):
  approval = { id: apr_+ULID, conversationId, agentId, shortCode: 1（占位，由中转重分配，见 §11 N-3）, kind:'tool_permission',
               summary: dialect.summarize(req.toolCall) ?? 标题+参数前 200 字, risk: classify(req.toolCall), options: req.options 映射
               （allow_once/allow_always/reject_once→reject/…）, status:'pending', decidedBy:null, expiresAt: now+approvalTimeout, createdAt }
  INSERT pending_permissions(approval_id, conversation_id, acp_request_id, options)
  sendToRelay(link, 'approval.request', {approval})；host → waiting_approval
on approval.decision{approvalId, optionId}:
  查 pending_permissions（已 resolved → 忽略，幂等）→ 回 ACP {outcome:{outcome:'selected', optionId}} → resolved_at=now → host → running
```
- 风险分级 `classify`（设计值）：写/删文件、执行 shell、网络外发 = `high`；读工作目录外文件 = `medium`；其余 `low`。具体 toolCall 字段因智能体而异，dialect 可覆盖（证据不足，TASK-021/081 夹具校对）。

## 5. 会话串行队列
### 5.1 规则
- **每个 (conversationId, generation) 同时最多一个在执行的轮次**；新 prompt 入 `prompt_queue`（state=queued），前一轮结束后出队（FIFO by `id`）。
- 全局 `Semaphore(maxSessions)` 控制**同时存活的子进程数**；会话已有存活进程时不占新名额。
- 公平性：调度器按 `enqueued_at` 最早的会话优先拿空闲名额（避免一个会话长期占用）。
- 背压：单会话排队上限 50（设计值），超出 → 回 `agent.output{kind:'error', body: callout(warn,"z1 排队已满（50），请稍后或 /stop")}`；中转侧也会看到 `agent.status.queueDepth`。

### 5.2 入队与幂等
```text
on agent.prompt{agentId, conversationId, generation, messageId, body, from}:
  namespace.guard(linkId, agentId)                       # 不属于本链接的 agent → error 帧 NOT_FOUND
  if emergencyFrozen → error 帧 EMERGENCY_STOPPED
  if generation < session.generation → 丢弃（过期代），ack
  INSERT OR IGNORE prompt_queue(message_id UNIQUE, …)     # 重复帧天然去重
  twin.capture? 否：用户指令的分身采集由中转经 twin.capture 下发（契约方向 relay→node），节点不重复采集
  wake(scheduler)
```
### 5.3 /clear 与 resume（REQ-F-019）
- `agent.clear{agentId, conversationId, newGeneration}`：取消在途轮次 → 旧 session 行 state=closed → 关闭进程 → 新建 `sessions(conversationId, newGeneration)`，新转录文件 `transcripts/<conversationId>/<generation>.jsonl`；旧代转录保留可查。
- `nativeSessionId` 写入 sessions，并随首个 `agent.output.nativeSessionId` 回传，使中转可按原生 id 检索（契约 agent.output 字段）。

### 5.4 空闲回收与上下文
| 条件 | 行为 |
|---|---|
| 空闲 ≥15 分钟 且 `supportsLoadSession=true` | 关闭进程；下次 prompt 用 `session/load` 恢复 |
| 空闲 ≥15 分钟 且 `supportsLoadSession=false`（v1 spec 表当前全部为 false，规划假设） | **不主动回收**；仅当 `maxSessions` 名额不足时按 LRU 驱逐，并向该会话发一条 system 消息：“z1 的对话因资源回收已重置上下文（旧记录保留，/history 可查）” |
> 理由：REQ-NF-002 的“15 分钟回收”与“会话可续接”（DEC-004）在不支持 loadSession 的智能体上冲突，优先保上下文；TASK-021/081 实测各智能体 loadSession 后更新 spec 表即自动生效。

## 6. 子进程监管（三平台差异）
### 6.1 启动
| 平台 | 命令解析 | 说明 |
|---|---|---|
| Windows | 优先 `spec.launch.windowsCommand`；否则在 PATH+PATHEXT 中解析 `command`。若解析结果为 `.cmd/.bat`，必须经 `cmd.exe /d /s /c` 并做参数转义 | Node 自 2024-04 安全修复后不允许无 shell 直接 spawn `.cmd/.bat`（部分确认，TASK-021 在 Node 22 实测）；`npx` 在 Windows 为 `npx.cmd` |
| macOS / Linux | `child_process.spawn(command, args, {detached:true})`：子进程成为新进程组组长 | 便于整组终止 |
| 共同 | `cwd` = workdir 或 worktree；`env` = 进程 env + `spec.launch.env` + 私有临时目录 `TMPDIR/TEMP=<dataDir>/tmp/<sessionId>`（借鉴 Orca privateTempDirectory）；`stdio: ['pipe','pipe','pipe']`；`windowsHide:true` | 模型 Key 不注入外部智能体（外部工具用自身账号，DEC-044） |
### 6.2 进程树终止
| 平台 | 方案 | 证据 |
|---|---|---|
| Windows | 方案 A：随节点分发自写小型 helper，把子进程加入设置了 `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` 的 Job Object，控制面退出时整树自动终止（DEC-021、DEC-041）。方案 B（兜底）：`taskkill /PID <pid> /T /F` | Node 无内置 Job Object API（推断）；A 需原生代码与签名，**证据不足**，TASK-021 实测后二选一，B 必须实现 |
| macOS/Linux | `process.kill(-pgid, 'SIGTERM')`，5 s 后仍存活 → `SIGKILL` | POSIX 进程组语义 |
| 孤儿清理 | 每个子进程启动时把 `{pid, pgid, startedAt, sessionKey}` 写入 `<dataDir>/run/children.json`；控制面启动时对仍存活且命令行匹配的 pid 执行终止 | 防止控制面崩溃后残留（Linux 无 Job Object 等价物，推断） |
### 6.3 健康
- ACP 请求超时：`initialize`/`session/new` 30 s；`session/prompt` 不设总超时（长任务），但 10 分钟无任何 `session/update` 时发 status 卡“可能卡住”（设计值）。
- 崩溃退避：1 s → 5 s → 30 s；15 分钟内 3 次 → `error`（§4）。
### 6.4 编码与路径（REQ-NF-006）
- stdout 为 ACP 协议，按 UTF-8 解析；stderr 先按 UTF-8 解码，出现替换字符且平台为 Windows 时用 `new TextDecoder('gbk')` 重解（Node 官方构建含 full-icu，部分确认）。
- 行尾：NDJSON 解析器接受 `\n` 与 `\r\n`。
- 长路径：workdir 以 `path.resolve` 规范化并按大小写不敏感比较（Windows/macOS 默认文件系统）后作为 `workdir_canonical`；>260 字符路径与 git worktree（需 `core.longpaths`）在 Windows 用例中覆盖，**待实测**。

## 7. 开机自启（REQ-F-001）
CLI：`workfleet-node autostart enable|disable|status`。
| 平台 | 机制 | 内容 |
|---|---|---|
| Windows | 当前用户 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 值 `WorkFleetNode` = `"<安装目录>\workfleet-node.exe" run --supervise --background`；无需管理员 | 崩溃重启由 `--supervise` 负责；任务计划程序（登录触发 + 失败重启）作为备选，是否需管理员权限证据不足，TASK-209 实测 |
| macOS | `~/Library/LaunchAgents/dev.workfleet.node.plist`：`RunAtLoad=true`、`KeepAlive={SuccessfulExit:false}`、`ProgramArguments=[…,"run"]`、日志到 `~/Library/Logs/WorkFleet/`；`launchctl bootstrap gui/$UID <plist>` | 用户级，登录后启动 |
| Linux | `~/.config/systemd/user/workfleet-node.service`：`ExecStart=<path> run`、`Restart=on-failure`、`RestartSec=5`；`systemctl --user enable --now workfleet-node` | 无图形登录的服务器需 `loginctl enable-linger <user>`（doctor 提示，不自动执行） |

## 8. 单实例锁（DEC-003）
```text
acquire(dataDir):
  path = <dataDir>/node.lock
  try open(path, 'wx') → 写 {pid, hostname, startedAt, nonce}；fsync；成功
  catch EEXIST:
     info = read(path)
     if info.hostname != os.hostname() → 拒绝启动（数据目录可能在网络盘，跨机器不抢锁；借鉴 Orca #29902）
     if isAlive(info.pid)（process.kill(pid,0) 不抛 ESRCH）→ 退出码 75，提示“已有实例运行（pid）”，CLI 子命令改为调用运行中实例的本机 API
     else → 陈旧锁：rename(path, path+'.stale-'+ts) 后重试一次 open('wx')（避免两个进程同时回收）
  二重保险：绑定 127.0.0.1:5100 失败 EADDRINUSE 且锁属他人 → 同样退出 75
release：正常关停时 unlink；崩溃留下的锁由下次启动按上面规则回收
```

## 9. relay-link（多中转，REQ-F-006、DEC-048）
- 每条链接独立：令牌（钥匙串条目 `workfleet/relay/<relayLinkId>`，库内只存 `token_ref`）、seq（`relay_links.node_seq`/`last_acked_relay_seq`）、outbox、dedupe、智能体命名空间（`agents.relay_link_id`）。
- **隔离规则**：从链接 L 收到的任何帧只能作用于 `relay_link_id=L` 的智能体/会话；向 L 发送的帧只包含 L 的数据；总控、分身按链接分区（分身事件 `refs.relayLinkId`）。违反即 `NOT_FOUND`（不泄露存在性）。
- 连接：`wss://<relay>/api/v1/node-gateway`，Bearer 令牌；发 `hello{protocolVersion:1, nodeVersion, os, lastAckedRelaySeq, agents}` → 收 `welcome` → 从 `welcome.lastAckedNodeSeq+1` 重发 `relay_outbox` 未 ack 帧。
- 断线重连：指数退避 1 s、2 s、4 s … 上限 60 s，±20% 抖动；收到 close 4401/403 DEVICE_REVOKED → 链接状态 `revoked`，停止重连并 p1 本机通知。
- 发送：先 `INSERT relay_outbox(seq=node_seq+1)` 再写 socket（at-least-once，ADR-005）；收到 `ack{upToSeq}` → 批量置 acked_at。
- 帧大小 >1 MiB → 不发送，改为截断正文 + “完整内容在本机，/history 可查”（PAYLOAD_TOO_LARGE，ADR-005）。

## 10. 其他模块要点
### 10.1 workspace-guard（REQ-F-032）
- 写入型智能体（`writeMode='write'` 且 spec `supportsWriteTools`）在会话启动时 `acquire(workdirCanonical)`：
  - 无活跃 exclusive 租约 → 插入 `write_leases(mode='exclusive')`（`ux_write_leases_active` 保证唯一）→ `lease.acquired`。
  - 已被占用：若 agent 配置 `onConflict='worktree'` 且目录是 git 仓库 → `git worktree add <dataDir>/worktrees/<agentId>-<ts> -b wf/<alias>/<ts>`，插入 `mode='worktree'`，会话 cwd 指向 worktree；否则拒绝 → `error` 帧 `AGENT_BUSY_WRITE_LEASE`（details.holderAlias）。
- 心跳：持有者每 30 s 更新 `heartbeat_at`；>5 分钟无心跳视为失效可抢占（设计值）。会话结束/回收 → release。
### 10.2 models（REQ-F-026、DEC-044）
- Key 只经 `POST/PATCH /local/v1/model-profiles` 请求体出现一次 → 写钥匙串 `workfleet/model/<modelProfileId>` → 库内 `key_ref`。日志 redact 规则覆盖 `apiKey`、`Authorization`。
- 每次调用后 `model_usage` 记 token 与 `cost_micros = in×inputPerMTokMicros/1e6 + out×outputPerMTokMicros/1e6`（ADR-013 部分确认）；超日/月上限 → `budget.exceeded` → `onExceed`（默认 degrade_to_rules）。
### 10.3 supervisor / meetings
见 DESIGN-020（总控）；本文只约束：总控是 `kind='supervisor'` 的智能体，运行在主设备（`/devices/{id}/primary`），不占 ACP 子进程，模型调用经 models 薄客户端（ADR-013）。
### 10.4 twin（REQ-F-029、DEC-049）
- 来源：中转下发 `twin.capture{event}`（用户本人指令、审批、纠正、命令）+ 节点本地产生的 `task_started/task_finished/routed/decision_point`。存 `twin_events`，软删除（`deleted_at`），导出 JSONL（不含已删除）。
### 10.5 Webhook 输入（REQ-F-008）
- `POST 127.0.0.1:5102/hooks/{hookId}`：校验 `X-WorkFleet-Signature: sha256=HMAC(secret, rawBody)`（常量时间比较；secret 取自钥匙串 `secretRef`），body ≤ 1 MiB；转为该 webhook 智能体的 `agent.output{kind:'final', priority: defaultPriority}` 回传中转，由绑定决定投递。hookId 与智能体的映射存 `agents.config.hookId`（见 §11 N-5）。
### 10.6 MCP（DEC-022）
- 127.0.0.1:5103，供本机智能体调用 `send_message({alias?, text, priority?})` 主动推送；调用方身份由 MCP 会话对应的 sessionKey 确定（会话启动时把带一次性 token 的 MCP URL 注入 `session/new.mcpServers`）。v1 只此一个工具（设计值）。
### 10.7 急停（REQ-F-033）
- 收到 `emergency.stop{reason}`：`kv_settings['emergency_stopped_at']=now` → 对所有 running 会话发 `session/cancel` → 调度器停止出队 → 各 agent 状态 `stopped` → ack。新 `agent.prompt` 回 `error(EMERGENCY_STOPPED)`。目标：中转发出后 5 s 内全部 stopped（DESIGN-010 §1/§3）。
- `emergency.resume`：清除标记，恢复出队（排队中的 prompt 不丢失）。

## 11. 与契约的差异 / 待办
| # | 发现 | 处理（不改契约） |
|---|---|---|
| N-1 | input-adapters.v1.json 中 13 个 ACP 智能体 `supportsLoadSession` 全为 false（规划假设） | §5.4 的回收策略据此降级；实测后更新 spec |
| N-2 | DEC-017“可编辑状态卡”需要“后一条 status 替换前一条”的关联键，`agent.output` 只有 `messageId`（全局唯一）与 `replyToId` | 临时约定：同一轮次的 status 帧共用 `replyToId=<触发该轮的入站 messageId>`，中转以 `(conversationId, replyToId, kind='status')` 找到上一张卡编辑；建议契约新增 `supersedesMessageId` 或 `turnId` |
| N-3 | `approval.shortCode` 为必填（1..99），但 shortCode 必须由中转按 tenant 分配 | 节点发送时填 1 占位，中转入库时重分配并以中转值为准；建议契约允许节点侧缺省 |
| N-4 | 无 relay→node 的智能体增删改帧（DESIGN-002 W-3）；本机控制台亦无“创建智能体”端点（node-local API 只有 adapters/detect） | 智能体从哪一侧创建目前两端都缺入口，**阻塞 TASK-026/027 闭环**，需契约补齐其一 |
| N-5 | Webhook 的 hookId/secretRef 无管理端点，node 0001 无 hooks 表 | 存 `agents.config`（`{hookId, secretRef, defaultPriority}`），密钥值经钥匙串；需契约补本机端点以生成 hookId 与写入 secret |
| N-6 | `transcript_fts` 未建同步触发器 | 由 `transcript-writer.ts` 在同一事务内写 `transcript_index` 与 `transcript_fts`（DESIGN-004 §3.2） |
| N-7 | 节点“缓存只读副本”（WF-ARCH §7：账号、项目、绑定…）无同步帧与表 | v1 节点不缓存绑定；需要的项目信息随 `agent.prompt.from`/agents.sync 携带；architecture §7 该格建议改为“v1 不缓存” |
| N-8 | 跨设备总控：工人智能体在设备 B、总控在主设备 A 时，没有 relay→node 的“转交给总控评审”帧 | v1 限制 supervisor 模式绑定的全部来源与总控在同一设备（中转创建绑定时校验 `ROUTE_INVALID`，DESIGN-006 §4.4） |
