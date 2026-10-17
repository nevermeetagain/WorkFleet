# 04 · Orca 深度分析（WorkFleet V0.0.2 修订版；原 V0.0.1 参考项目）

> 分析对象：https://github.com/stablyai/orca
> **【V0.0.2更新】修订版本**：`main` @ `fd1c6a592cc98f4ae6348f2bb101337a4b6f90a6`（2026-10-16 18:15 -0700 = 2026-10-17 09:15 +08:00，#29902），`package.json` 版本仍 `1.4.214`。基线 `a8e3734e` 为其祖先，相隔 330 个提交（+99,839/−26,971，2,342 文件）。本文件只修订最新代码中变化的内容，以【V0.0.2更新】标注；未标注段落为 V0.0.1 原文，已逐项核对其引用文件在 HEAD 仍存在。完整架构与演进见 `14-Orca技术架构与实现路线.md`。
> 【V0.0.2更新】工作树：`/workspace/work/refs/orca`（`git fetch --depth 300` 后检出 HEAD）；全历史：`/workspace/work/refs/_hist/orca.git`（14,712 提交）。注意：GitHub API 显示 2026-10-17 09:30 +08:00 仍有新 push，本修订不含此后提交。
> 分析版本：`main` @ `a8e3734e11b7695519f3c0859007408b0df6fe84`（提交时间 2026-10-16 13:58 +08:00，“test: remove setup sequencing shell inspection seam (#29399)”），`package.json` 版本 `1.4.214`
> 本地路径：`/workspace/work/refs/orca`（`git clone --depth 1`，36,460 个受控文件；`src/` 非测试 TS/TSX 16,306 个）
> 分析日期：2026-10-16（Asia/Shanghai）
> 方法：先读 `AGENTS.md`（工程约束）与 `skill-guides/orchestration*`（编排契约），再沿 `src/main/{acp,runtime/orchestration,automations,ai-vault-search,notifications,server}` 与 `src/shared/automation-*`、`src/cli/specs/*` 逐层读源码。仓库体量极大，**只读与需求相关的子系统**，其余标 `证据不足`。未构建、未运行（Electron + 原生模块）。
> 证据标签：`已确认` · `部分确认` · `证据不足` · `存在缺陷` · `暂不执行`

---

## 0. 一句话结论

Orca 是 **“并行智能体开发 IDE”**（Electron 桌面 + `orca serve` 无头运行时 + 移动伴侣 App + 云中继/推送），它把 **45 个编码 CLI/智能体条目**（【V0.0.2更新】基线写“40 种”有误：`tui-agent-display-names.ts` 在基线与 HEAD 均为 45 项，含 claude-agent-teams、opencode2、qoder-cn 等变体）作为一等公民管理：每个跑在独立 worktree/终端或结构化会话里；并内建 **监督式编排（Run/Task/Dispatch/Mailbox/ask-reply/decision gate/escalation）**、**定时自动化（cron/RRULE 预设）**、**`/clear` 会话谱系** 与 **跨智能体会话转录全文检索（含 resume_command）**。

它是五个参考项目中 **“输入端（多 CLI）+ 总控编排 + 定时 + 会话检索”覆盖最广** 的一个；但 **输出端只有自家桌面通知与自家手机 App（经自建中继/APNs/FCM）**，**没有任何 IM（微信/飞书/QQ/钉钉/Discord/Telegram）**，也没有“通知模式/团队模式”的多对多路由；总控的“AI 自动分解需求/开会”在代码中**明确尚未实现**（由一个智能体按 skill 指南扮演 coordinator）。

- 需求匹配度（加权估算）：**约 45%**（见 §2）。
- 复用结论：**作为“输入端运行时 + 总控编排协议 + 会话检索”的首选参考；按模块抽取/移植（MIT），不整体 fork**。整体 fork 不现实：Electron 主进程强耦合、体量巨大（单 `src/main` 顶层 665 项）、跨平台/SSH/WSL 约束复杂。

---

## 1. 仓库事实（What）

### 1.1 社区与许可（GitHub API，2026-10-16 查询）

| 项 | 值 | 标签 |
|---|---|---|
| Stars / Forks / Open issues | 93,729 / 5,979 / 8,524（【V0.0.2更新】2026-10-17 GitHub API：94,511 / 6,042 / 8,475） | 已确认 |
| 创建 / 最近 push | 2026-03-17 / 2026-10-16（分析当天仍在提交） | 已确认 |
| 许可证 | MIT（`LICENSE`：Copyright (c) 2026 Lovecast Inc.）；`cloud/README.md` 声明云中继源码同受根 MIT 覆盖 | 已确认 |
| 主语言 | TypeScript（Electron/React/Node），移动端 Expo/React Native，云端独立 pnpm workspace | 已确认 |
| 发布 | 桌面 macOS/Windows/Linux；iOS App Store、Android APK（README） | 已确认（README 文本） |

活跃度：提交以 PR 编号 #29399 计，迭代极快；open issues 8.5k 说明用户量大、问题积压也大 → **社区极活跃，但 API/内部结构变动频繁，移植后跟进成本高**（`部分确认`）。

### 1.2 技术栈与关键依赖（`package.json`）

electron 43.7.8、electron-vite 6、react 19.2、zustand 5、tailwindcss 4.3、@xterm/xterm 6.1-beta、node-pty 1.1、ws、vitest 5；SQLite 使用 Node 内置 `node:sqlite`（`src/main/sqlite/sqlite-statement.ts:1`）。

【V0.0.2更新】基线→HEAD 依赖仅新增 `fflate 0.8.3`；`build:cli` 改用 `config/tsconfig.build.cli.json`（`git diff a8e3734e HEAD -- package.json`）。补充核对：`engines.node: 24`、TypeScript ^7.0.2、zod ~4.6.5、@anthropic-ai/claude-agent-sdk 0.3.284、pnpm 12.8.1；`node:sqlite` 仍为底座（`src/main/sqlite/sync-database.ts:2`）。

### 1.3 与需求相关的子系统地图

| 子系统 | 路径 | 作用 |
|---|---|---|
| ACP 客户端 | `src/main/acp/`（json-rpc peer、session setup、permission、dialects、subagents…） | 以 ACP 驱动 grok/opencode/omp 等 |
| 结构化会话 | `src/main/claude/claude-agent-sdk-*`、`src/main/codex/codex-app-server-*`、`src/main/native-chat/` | Claude 走 Agent SDK/stream-json，Codex 走 app-server，统一为“structured session” |
| TUI 智能体 | `src/shared/tui-agent-display-names.ts`（45 项，【V0.0.2更新】更正）+ `src/main/pty/`、`agent-hooks/` | PTY 终端 + 钩子上报状态 |
| 编排 | `src/main/runtime/orchestration/`、`src/cli/handlers/orchestration/`、`skill-guides/orchestration*` | Coordinator/Worker 监督模型 |
| 自动化 | `src/main/automations/`、`src/shared/automation-*` | 定时运行 prompt |
| 会话检索 | `src/main/ai-vault/`、`src/main/ai-vault-search/` | 各 CLI 转录索引 + FTS5 |
| 通知 | `src/main/notifications/notification-delivery-service.ts` | 桌面横幅 + 手机推送扇出 |
| 远程/移动 | `src/main/server/serve-*`、`src/cli/specs/serve.ts`、`mobile/`、`cloud/apps/{relay,push}` | 无头运行 + 配对 + 中继 + APNs/FCM |
| 【V0.0.2更新】纯 Node 守护进程 | `src/main/orcad/`（`main.ts:1` “Executable entry for `orcad`”；`orcad-automations.ts:1-24` 也执行调度；`orcad-instance-lock.ts` 数据根单实例锁） | 无 Electron 的设备端常驻运行时；基线漏列 |

---

## 2. 需求匹配度（逐条，含 4 个场景）

| # | 需求 | 结论 | 证据 / 说明 |
|---|---|---|---|
| R1 | 后台配置管理 | **部分** | 桌面设置、项目分组（`src/main/project-groups/`）、profile（`src/main/orca-profiles/`）、`orca.yaml`；但无“输入↔输出模式”配置。 |
| R2 | 管理模式 多输入→1 输出 | **部分** | 多输入：45 个 agent 条目（`tui-agent-display-names.ts`，【V0.0.2更新】更正），并行 worktree；1 输出：桌面 + 手机 App 汇总通知/状态，“Monitor and steer your agents from your phone”（README Mobile Companion）。输出端不是 IM → 部分。 |
| R3 | 通知模式 1→多 | **不支持** | 通知只发给本机桌面与已配对手机（`notification-delivery-service.ts:27,100-115 dispatchMobileNotification`）；无多接收者/群发。 |
| R4 | 团队模式 多→多 | **不支持** | 无“项目→通道”路由表；`@worktree:<id>` 等组地址仅用于智能体之间（`skill-guides/orchestration/references/messaging-and-gates.md` Addresses 段）。 |
| R5 | 定时任务（单次/工作日/休息日/每日/每周/每月） | **部分** | 预设：hourly/daily/weekdays/weekly/custom（`src/shared/automation-schedules.ts:10-26`），custom 为 cron（vixie 方言，`automation-cron-field-parsing.ts:1`）或 RRULE；60 秒 tick（`src/main/automations/service.ts:41 DEFAULT_TICK_MS`、`:120 setInterval`），错过宽限处理 `missedBeyondGrace`（`service.ts:275`）。**单次（run once）未检出**（在 `src/shared/automation*`、`src/main/automations` 中检索 `once/oneShot/runOnce` 无命中 → `部分确认`）；【V0.0.2更新】RRULE 解析器只接受 `FREQ=HOURLY|DAILY|WEEKLY`，只读 BYHOUR/BYMINUTE/BYDAY，`COUNT/UNTIL` 被丢弃（`src/shared/automation-schedule-parsing.ts:39-68`），错过策略仅 `run_once_within_grace`（`automations-types.ts:8`）→ **单次不支持 `已确认`**；**休息日/节假日无**；每月可用 cron `0 9 1 * *` 表达（推断）。 |
| R6 | 一端 `/clear` 新开对话 | **支持（本地）/部分（远程 IM）** | `/clear` 谱系：`clearedInto(record)`（`src/main/runtime/orchestration/structured-session-lineage.ts:24`），runs 表记录 “for a /clear'd chat, its lineage root's” session（`db/schema/create-core-tables-sql.ts:12-13`）。手机 App 可向会话发消息（README），但不是 IM。 |
| R7 | 两端对话记录、按 session/resume ID 查询 | **支持（输入端侧）** | `sessions(agent, session_id, file_path, title, cwd, branch, resume_command, content_hash…)` + `messages_fts USING fts5(user_text, assistant_text, tool_text, identifiers)`（`src/main/ai-vault-search/session-search-schema.ts:24-90`）；ai-vault 读取 claude/codex/openclaw/opencode/antigravity/omp 等转录（`src/main/ai-vault/*-session-*`）。【V0.0.2更新】`session-search-schema.ts` 行号变为 sessions `:25-51`、files `:55`、messages_fts `:89-91`（打开/重建逻辑抽到共享 `sqlite/versioned-cache-database`，schema 仍 v6）；解析缓存改为每转录一行 SQLite（`ai-vault/session-parse-cache-database.ts`，#29401）；手机端可“在新 CLI 中恢复”历史会话（#29783）。**IM 侧记录不存在**。 |
| R8 | 分身数据自动更新 loop | **不支持** | 未发现用户画像/人格模块（`src/main/memory/` 是进程内存采样：`process-memory-metric.ts` 等，非知识记忆）。 |
| R9 | 知识库 | **不支持/弱** | 仅会话检索（全文），无向量记忆、无项目设计/目录图谱。 |
| R10 | 总控：组织会议、员工扮演、分配任务 | **部分** | Run/Task/Dispatch + DAG（`tasks.deps`）+ 并发上限（`coordinator.ts:36 MAX_CONCURRENT_DEFAULT = 4`）+ 自动建终端派工（`coordinator.ts:241-305`）。**但“AI 分解需求”未实现**：`coordinator.ts:146` “decomposition isn't implemented yet — tasks must be pre-created … AI-driven decomposition is a future phase”。实际由一个 agent 按 `skills/orchestration/SKILL.md` 扮演 coordinator，用 `orca orchestration task-create/worker-start` 手动派工。**无多 agent 会议/讨论原语**（只有 ask/reply、send、group 地址可拼出）。 |
| R11 | 总控把关、只上报重要事项 | **部分** | 消息类型 `status/dispatch/worker_done/merge_ready/escalation/handoff/decision_gate/question/heartbeat` 与 `priority normal/high/urgent`（`create-core-tables-sql.ts:23-49`）；escalation→失败计数→熔断（`coordinator-escalation-triage.ts`，3 次后 `circuit_broken`）；decision gate（`create-graph-tables-sql.ts:188 decision_gates`）。**外部上报策略为空**：`coordinator.ts:226` “this stays a hook for future policies (auto-reassign, external notify)”。 |
| R12 | 总控自定义模型、skill 配置 | **部分** | worker 可指定 `--agent/--model/--effort`（`skill-guides/orchestration.md` “Model or effort selection…”）；skills 体系（`skills/`、`skill-guides/`、`src/main/skills/`）。总控本身是“任一 agent + orchestration skill”，模型即该 agent 的模型。 |
| R13 | 随时与总控对话不影响执行 | **支持（机制）** | coordinator 与 worker 是不同终端/会话；coordinator 通过 `check --wait` 邮箱轮询（`messaging-and-gates.md` Coordinator delivery loop），用户可直接在 coordinator 会话中对话；worker 在检查点读 follow-up（`orchestration.md` Worker obligations 3）。 |
| R14 | 总控运行在设备上 | **支持** | 桌面本地；或 `orca serve` 无头运行（`src/cli/specs/serve.ts:6-9`），支持 SSH/WSL/远端主机。 |
| S1 | 3 项目×6 工具→微信 ClawBot | **部分** | 3 项目×6 工具并行管理 ✔（项目分组 + worktree + 45 agent 条目）；**微信 ✘**（只能是 Orca 手机 App）。 |
| S2 | 飞书数据管理，3 输入→2 输出 | **不支持** | 无飞书、无多输出。 |
| S3 | 主项目+子项目，用总控统一开发 | **部分（最接近）** | 监督式编排 + DAG + worktree 隔离 + 合并（`merge_ready`）正是此场景；缺 AI 自动分解与 IM 汇报。 |
| S4 | 每日 9 点推送给大量用户 | **不支持** | 自动化是“定时跑一个 agent prompt”，不是群发；接收端仅本人设备。 |

**加权估算**（核心 R1–R4 40%、扩展 R5–R9 30%、总控 R10–R14 30%）：核心 ≈ 20%、扩展 ≈ 45%、总控 ≈ 65% → **≈ 0.4×20 + 0.3×45 + 0.3×65 ≈ 41%**；考虑输入端覆盖（45 agent 条目、ACP+SDK+PTY 三通路）是用户首要痛点的一半，上调为 **≈ 45%**（`部分确认`，主观加权）。

---

## 3. 关键调用链（How，代码级）

### 3.1 ACP 会话建立（输入端适配的核心）

`setupAcpSession`（`src/main/acp/acp-session-setup.ts:34-63`）：
```
无 sessionId           → request('session/new')                         :42
有 sessionId 且 agentCapabilities.loadSession && 偏好非 resume → 'session/load'   :47-53
有 sessionId 且 sessionCapabilities.resume  → 'session/resume'           :55-60
都不支持               → AcpRpcError(-32601, 'cannot load or resume')    :62
认证失败 → AcpAuthRequiredError 携带 initialized.authMethods 重试          :65-80
```
- ACP 启动规格“以数据描述”（`acp-launch-specs.ts` 头注释：“adding an agent is one more row (plus a dialect…)”），当前行：`grok`(:113)、`opencode`(:157)、`omp`(:189)；方言扩展在 `acp-dialects/{grok,opencode,omp}-dialect.ts`。【V0.0.2更新】HEAD 行号为 `grok`(:112)、`opencode`(:156)、`omp`(:188)、`ACP_LAUNCH_SPECS`(:216)；spec 新增/明确字段 `managedRuntime`（用户要求时才安装到数据目录，启动绝不安装，#28460/#29023）、`privateTempDirectory`（每进程私有 temp，#28462）；`fullAccess` 改为“chat 自己的 Full access 权限模式”而非全局设置（`acp-launch-specs.ts:68`，#29335）。另核实：`initialize` 声明 `clientCapabilities:{fs:{readTextFile:false,writeTextFile:false},terminal:false}`（`acp-session-runtime.ts:110`），协议版本固定 1（`generated/acp-protocol.generated.ts:200`）；ACP 层整体始于 2026-10-05（#24990）。
- 模型发现两种方式：从 `initialize` 回包或执行列表命令（`acp-launch-specs.ts` `AcpModelDiscovery`），**绝不为此调用 authenticate/session/new**。
- Claude 走 Agent SDK 进程（`src/main/claude/claude-agent-sdk-process-spawn.ts`），Codex 走 app-server（`src/main/codex/codex-app-server-capability-cache.ts`），其余 TUI agent 走 PTY + hooks。
→ **WorkFleet 输入端适配器应采用同样的“三通路”分层：ACP（首选）/ 厂商 SDK 结构化流 / PTY 兜底**，并把“load vs resume”能力协商照搬（这是按 resume ID 续聊与查历史的前提）。

### 3.2 编排：Coordinator tick 循环

`Coordinator.executeLoop`（`src/main/runtime/orchestration/coordinator.ts:94-140`）→ `decompose()`（:147，仅校验已存在任务）→ 每 `pollIntervalMs=2000`（:35）执行 `tick()`（:159）：
```
processMessages()          :168  读 coordinator 未读邮件：worker_done/heartbeat→reconcileLifecycleMessage；
                                 escalation→applyEscalationToDispatch（熔断）；decision_gate→openDecisionGateFromMessage
processEscalations()       :225  空钩子（外部通知待实现）
reblockTasksWithPendingGates      有未决 gate 的任务重新阻塞
warnStaleDispatches               心跳超时告警
dispatchReadyTasks()       :229  ready 任务 × 空闲终端，受 maxConcurrent=4 限制；无终端则每 tick 最多新建 1 个（:252）；
                                 派工前探测 worktree 基线漂移（stale-base 拒绝）
checkConvergence()         :307  DAG 全部终态则结束
```
Worker 侧契约（`skill-guides/orchestration.md` Worker obligations）：只做当前 Task；阻塞问题用 `ask`；按节奏心跳；检查点 `check` 读 follow-up；完成时**恰好一次** `worker_done --outcome succeeded|failed` 附三句摘要。

【V0.0.2更新】结构化会话的邮件提示投递改为 `delivery:'now'`，若会话有待答的可操作提示（如权限请求）则 `held`，提示消失后再投；成功后循环重新派生新到邮件（`structured-mailbox-pointer-host.ts`、`structured-mailbox-pointer-delivery.ts`，#28540）。熔断阈值精确出处：`db/dispatch-context/dispatch-circuit-breaker.ts:2`（`DISPATCH_CIRCUIT_BREAK_FAILURES = 3`）。`coordinator.ts` 本身未变，§3.2 行号仍有效。

CLI 动词全集（`src/cli/specs/orchestration*.ts`）：`run-create/run-use/run-show/run-list/run-current, task-create/task-list/task-update, worker-start/worker-list/worker-show/worker-read/worker-stop/worker-abandon/worker-release/worker-retain, dispatch/dispatch-show, send/check/inbox/ask/reply, gate-create/gate-list/gate-resolve, coordinator-start/coordinator-stop, request-show, reset`。

### 3.3 编排数据模型（SQLite）

`create-core-tables-sql.ts` / `create-graph-tables-sql.ts`：
- `runs(id, objective, coordinator_handle, coordinator_orca_session_id, consumer_generation…)`（core:5-21）
- `messages(id, run_id, from_handle, to_handle, subject, body, type∈{status,dispatch,worker_done,merge_ready,escalation,handoff,decision_gate,question,heartbeat}, priority∈{normal,high,urgent}, thread_id, payload, read, sequence AUTOINCREMENT, delivered_at…)`（core:23-49，索引 `idx_inbox(to_handle,read)`、`idx_thread`）
- `deliveries`（core:90，FIFO 批次 + ack；`messaging-and-gates.md`：一次最多 50 条，ack 前重放同一批）
- `tasks(id, run_id, parent_id, spec, status∈{pending,ready,dispatched,completed,failed,blocked}, deps JSON, result…)`（graph:115-136）
- `dispatch_contexts(id, task_id, assignee_handle, assignee_orca_session_id, status∈{pending,dispatched,completed,failed,circuit_broken}, failure_count, depth, last_heartbeat_at…)`（graph:140-183）
- `decision_gates(id, task_id, question, options, status∈{pending,resolved,timeout}, resolution)`（graph:188-199）
- `coordinator_runs(id, spec, status, poll_interval_ms…)`（graph:208-218）
- 另有 `worker_dispatches`、`worker_terminal_resources`、`worker_terminal_archives`、联邦表 `federated_dispatches/remote_questions/federation_relay_items`（跨主机派工）。

【V0.0.2更新】编排 schema 版本 `SCHEMA_VERSION = 43`（`db/contract-constants.ts:23`），基线→HEAD 表结构未变。

→ **这是 WorkFleet 总控持久层最直接可移植的 schema**：把 `to_handle` 扩展为“IM 通道地址”，即可让总控邮箱同时承载“员工↔总控”与“总控↔用户 IM”。

### 3.4 自动化调度

`AutomationService.start`（`service.ts:115-133`）：`setInterval(evaluateDueRuns, 60s)`；启动时补跑与漂移报告。`evaluateDueRuns`（:233-266）逐条判断 `enabled && nextRunAt<=now`，单条异常隔离（#16303 注释）；`evaluateAutomation`（:268起）：取最近应发生时刻 → 超宽限记 missed → 解析执行目标（本地/SSH/WSL）→ 拒绝原因去重（避免 `*/5` 每天写 288 行）→ `createRun` + `requestDispatch`。`Automation` 记录字段：`name, prompt, precheck, agentId, extraAgentArgs, runContext, executionTargetType/Id, schedulerOwner, workspaceMode…`（`src/shared/automations-types.ts:91-121`）。CLI：`automations list/show/create/edit/remove/run/runs`（`src/cli/specs/automations.ts`）。【V0.0.2更新】`automations runs` 新增 `--limit/--cursor` 分页（每页 ≤100，`src/cli/specs/automations.ts:114-129`，#29446）；`service.ts` 未变。

### 3.5 会话检索

ai-vault 扫描各 CLI 转录目录 → `session-search-indexer.ts`/`index-writer.ts` 增量写入（`files.byte_offset` + `state current/due/failed`，`session-search-schema.ts:54-74`；【V0.0.2更新】HEAD 为 `:55-76`）→ FTS5 `unicode61 tokenchars '_.-/+'`（:20）检索，bm25 分列加权，`fts5vocab` 用于纠错（`session-search-query-schema.ts:11`、`session-search-typo-repair.ts`）。**按 agent + session_id 精确查找，并直接给出 `resume_command`** —— 正好满足“按 session/resume ID 查询对话记录”。
⚠️ 中文分词：`unicode61` 对 CJK 按单字切分，中文检索质量 `证据不足`（需实测或改用 trigram/jieba）。

### 3.6 通知扇出

`createNotificationDeliveryService`（`notification-delivery-service.ts`）：先设托盘注意力 → 若已配对运行时则 **mobile fan-out 在桌面早退之前**（文件头注释 + :100-115）→ 桌面原生横幅；按 `attentionKey/worktreeId` 去重（`dedupeKeyFor`）。手机推送经 `cloud/apps/push`（APNs/FCM，按主机配额，`cloud/README.md` Mobile push gateway 段），手机↔桌面经 `cloud/apps/relay` 中继拼接 WebSocket（本地 RPC 端口 6768，`mobile/README.md:7`）。

---

## 4. 全方位维度分析

| 维度 | 现状（证据） | 对 WorkFleet 的意义 |
|---|---|---|
| 前端 | React 19 + zustand + Tailwind 4 + shadcn，严格设计系统（`docs/STYLEGUIDE.md`，lint 强制）；自动化编辑器组件 `src/renderer/src/components/automations/*`（含 `AutomationCustomCronPanel.tsx`） | 定时任务编辑 UI、会话列表 UI 可直接参考交互 |
| 后端 | Electron 主进程 + 可无头 `orca serve`；`@orca/process-host` 统一子进程；守护进程化终端（`src/main/daemon`） | 输入端运行时必须常驻、可在服务器无头跑——Orca 证明了这一形态 |
| 数据 | 本地 SQLite（`node:sqlite`）；编排库、会话检索库、profile-state 库分离 | 单机零依赖；WorkFleet 设备端总控适合同构（SQLite + 可选 PG） |
| 交互 | 桌面 + 手机 App + CLI（agent 自身也用 CLI 交互） | “agent 通过 CLI 调用编排原语”是让任意 CLI 当员工/经理的关键技巧 |
| 逻辑 | 监督式编排、FIFO 邮箱 + ack、熔断、gate、联邦派工、“absence ≠ death” 活性判定（`AGENTS.md` SSH Use Case） | 总控可靠性设计的金标准 |
| 组件 | ACP json-rpc peer、session setup、launch spec 表驱动、cron 解析、FTS 索引器、通知去重 | 均可独立抽出（需剥离 Electron 依赖） |
| 复用 | MIT；但模块间依赖 `runtime`、`native-chat` host、Electron IPC；`AGENTS.md` 要求“Reuse Before Reimplementing” | 抽取成本中-高 |
| 拓展 | 新增 ACP agent=加一行 spec（+方言）；新增 TUI agent 需 hooks + 屏幕规则（`AGENTS.md` Agent Terminal Screens） | 输入端扩展模型可直接沿用 |
| 性能 | 编排默认并发 4；tick 2s；自动化 tick 60s；FTS 基准（schema 注释给出 105MB 语料 p95 对比）；大量 `bench:*` 脚本 | 对单机数十会话足够；百级以上需重新压测（`证据不足`） |
| 配置 | `orca.yaml`、profiles、per-workspace env（`skills/orca-per-workspace-env`）、自动化 extraAgentArgs | 可参考 |
| 知识库 | 无（仅检索） | 需 Hindsight 补 |
| 响应 | 邮箱是 durable enqueue，wake/nudge 尽力而为（`orchestration.md` “A successful send proves durable enqueue…”） | IM 回执语义应同样区分“已入队”与“已处理” |
| 存储 | 本地文件 + SQLite；终端回滚持久化；transcript 归档 | 设备端友好 |
| 资源 | Electron 桌面重；`orca serve` 较轻但仍需 Node + 原生模块（node-pty） | 设备端可接受 |
| 【V0.0.2更新】资源上限 | `orca serve` 文档新增可选每终端内存/交换上限 `ORCA_TERMINAL_MEMORY_MAX` / `ORCA_TERMINAL_MEMORY_SWAP_MAX`（Linux systemd user scope）；显式 `--port` 被占即报错，默认 6768 被占则换端口（`src/cli/specs/serve.ts` notes，#29432） | 设备端总控可借鉴“每员工进程资源上限” |
| 安全 | 工作区信任（`agent-workspace-trust*.ts`）、凭据文件保护（`credential-file-protection.ts`）、编排 DB 文件权限（`db/database-file-permissions.ts`）、终端输出脱敏（`worker-terminal-redaction.ts`）、配对 X25519 + 挑战（`cloud/README.md`）、`--grant-desktop-control` 显式授权 | 远程控制/IM 下发命令的安全模型可借鉴 |
| 许可证 | MIT | 可移植，保留版权声明 |
| 社区 | 93.7k★，8.5k open issues，日更 | 强，但变更频繁 |

---

## 5. 深度分析（四轮方法）

### 5.1 第一轮 5W1H

- **What**：Orca 已实现多 CLI 并行运行与状态汇总、监督式编排协议、定时自动化、`/clear` 谱系、会话检索、手机远程操控。缺：IM 输出、多对多路由、通知群发、AI 自动分解/会议、重要度外发策略、知识库/画像。已证实：§3 全部 schema 与调用链；未证实：运行期行为与中文检索效果。
- **Why**：用户痛点是“多工具 × 单微信反复扫码”。Orca 解决的是“多工具 × 单人桌面/手机”，**输入侧问题域一致、输出侧载体不同**。根因：Orca 把输出端做成自有 App（可控、可加密、可推送），而 WorkFleet 必须复用第三方 IM（受平台限制，如 iLink 同用户仅路由到最新 bot —— 见 01 报告）。
- **Where/When**：可借鉴代码在 `src/main/acp`、`src/main/runtime/orchestration`、`src/main/automations`+`src/shared/automation-*`、`src/main/ai-vault-search`。应在 WorkFleet“输入端适配层”和“总控引擎”设计阶段最先引入。端口：Orca 本地 RPC 6768；与 WorkFleet 3000/3333 无冲突。
- **Who**：Lovecast Inc./stablyai 维护；WorkFleet 侧输入端适配、总控、调度三个模块负责人分别消化。
- **How**：按模块“读契约→剥离 Electron/IPC→保留纯逻辑+schema→补测试”；优先移植 schema 与状态机，而非直接复制大文件。
- **What if**：
  - 若 Orca 未来自带 IM 通道 → 可考虑直接以 Orca 为输入端运行时、WorkFleet 只做 IM 网关（需持续关注，`证据不足`）。
  - 若 ACP 版本升级字段变化 → Orca 已用 zod schema 校验（`acp-session-setup.ts:32 Request<T> … z.ZodType<T>`），移植时保留 schema 校验与能力协商即可降级。
  - 若部署在纯 Linux 服务器 → `orca serve` 可行，但 Claude/Codex 需各自登录态；WorkFleet 需管理多账号凭据（Orca 有 `claude-accounts/codex-accounts` 可参考）。
  - 若用户不需要总控 → Orca 的编排可完全不启用，输入端运行时仍有价值。

### 5.2 第二轮 苏格拉底追问

| 结论 | 追问 | 回答 |
|---|---|---|
| “无 IM 输出” | 会不会有插件/集成？ | `git grep -il "telegram\|feishu\|lark\|dingtalk\|wechat\|discord.com/api\|slack.com/api" -- src cloud` 非测试无命中；有 jira/linear/github 等工单集成（`src/main/{jira,linear,github}`），非 IM。→ `已确认`（仅当前提交） |
| “AI 自动分解未实现” | 也许在别处由 LLM 实现？ | `coordinator.ts:146` 注释明确；`skills/orchestration/SKILL.md` 把分解交给扮演 coordinator 的 agent 自己用 `task-create`。所以“分解”存在于 **agent+skill** 层，不在引擎层。→ `已确认` |
| “会话检索可满足按 resume ID 查询” | 是否覆盖用户的 6 个工具？ | 覆盖 claude/codex/openclaw/opencode/antigravity/omp 等转录（`src/main/ai-vault/*`）；Cursor/Coze/Zcode 的转录支持 `证据不足`（`tui-agent-display-names` 含 cursor、zcode，但 ai-vault 文件名中未见对应 collector）。→ `部分确认`。【V0.0.2更新】**更正**：基线提交中已有 `session-scanner-cursor-*`、`session-scanner-zcode-*`（`git ls-tree a8e3734e src/main/ai-vault/`），HEAD 按文件名统计 18 个 agent 专用解析器（antigravity/cline/codebuddy/codex/copilot/cursor/devin/droid/gemini/grok/hermes/jcode/kimi/kiro/muse/opencode/qoder/zcode…）→ Cursor、Zcode `已确认`；**Coze 无解析器 `已确认`**。 |
| “定时不支持单次” | 会不会用 RRULE COUNT=1？ | `automation-schedules.ts` 的 custom 允许 RRULE 表达式（:24-25），COUNT=1 是否被调度器尊重未验证 → `证据不足`。【V0.0.2更新】已核实：`parseRrule` 丢弃 COUNT/UNTIL 且只认三种 FREQ（`automation-schedule-parsing.ts:39-68`）→ **不支持，`已确认`** |

### 5.3 第三轮 双向钢人论证

**主张 A：以 Orca 为 WorkFleet 的“输入端运行时”，WorkFleet 只做 IM 网关 + 路由 + 总控外发策略。**
- 支持：输入端覆盖最全（45 agent 条目，三通路）、会话恢复/检索/`/clear` 现成、`orca serve` 可无头、编排协议成熟、MIT。
- 反对：① 无公开稳定的“外部程序订阅 Orca 事件/注入消息”的 API 契约（需走其 RPC/CLI，版本漂移风险高，`AGENTS.md` 明言 mixed versions 是常态）；② 用户不一定愿意装 Orca；③ 依赖一个日更项目的内部 CLI 输出格式，耦合脆弱。
- 裁决：反对意见 ① 未被排除（`证据不足`：未审计 runtime RPC 是否对第三方开放）→ **作为 V0.0.1 的“可选集成”而非必需底座**。

**主张 B：移植 Orca 的模块（ACP client、编排 schema/状态机、调度解析、会话索引）到 WorkFleet 自有运行时。**
- 支持：MIT；模块边界清晰（schema 与纯函数多）；可去 Electron 化；完全掌控。
- 反对：抽取工作量大；后续无法自动享受上游修复。
- 裁决：工作量可接受（只取 4 个子系统的核心）→ **主张 B 成立，作为主路线**；主张 A 作为备选集成。

### 5.4 最终判断

1. **结论**：Orca 是 **WorkFleet 输入端与总控编排的首要参考与代码移植来源**；不整体 fork；输出端/路由/群发/知识库需另补（`部分确认`）。
2. **依据**：§2、§3。
3. **代码证据**：`acp-session-setup.ts:34-63`、`acp-launch-specs.ts:113,157,189`、`coordinator.ts:36,146,159-305`、`create-core-tables-sql.ts:5-49`、`create-graph-tables-sql.ts:115-218`、`automation-schedules.ts:10-26`、`service.ts:41,115-133,233-300`、`session-search-schema.ts:20-90`、`structured-session-lineage.ts:24`、`notification-delivery-service.ts:27,100-115`、`cli/specs/serve.ts:6-9`。
4. **命令证据**：clone 成功；GitHub API；`git ls-files` 计数；`git grep` IM 无命中。
5. **前提**：基于 `a8e3734`（当天最新）；未运行。【V0.0.2更新】已对 `fd1c6a5` 复核：结论不变；ACP/编排投递/会话缓存有增量变化（见各节标注）。
6. **局限**：仓库巨大，仅审读相关子系统；运行期并发、资源占用、中文 FTS 未验证。
7. **未验证**：RRULE COUNT=1；Cursor/Zcode/Coze 转录读取；runtime RPC 对第三方的开放度。【V0.0.2更新】前两项已核实（COUNT 不支持；Cursor/Zcode 有解析器、Coze 无）；仅剩 runtime RPC 开放度 `证据不足`。
8. **风险**：上游高速变更导致移植件过时；Electron 依赖隐性渗透到被移植模块。
9. **下一步**：(a) 精读 `src/main/acp/acp-json-rpc-peer.ts`、`acp-permission-requests.ts` 作为输入端适配器蓝本；(b) 把编排 schema 与 PentAGI 状态机合并成 WorkFleet 总控 ER 图；(c) 对 FTS5 中文检索做最小实验。
10. **是否进入下一阶段**：**允许**进入“输入端适配层 + 总控持久层”设计阶段。

---

## 6. 缺口与补齐方案

| 缺口 | 补齐 | 来源 |
|---|---|---|
| IM 输出（6 种） | 统一 `ChannelAdapter`：connect/login(扫码)/send/receive/ack；会话映射 `channel_user ↔ route` | WechatClawbot（iLink）、OpenClaw/AstrBot 适配器（`20-同类开源/`）、`30-协议与端点/04-统一适配器接口设计.md` |
| 管理/通知/团队路由 | `routes(source_selector, sink_selector, mode, filters, priority_threshold)` 多对多表；消息总线扇入扇出 | 自研；字段借鉴 Orca `messages.priority`、`@group` 地址 |
| 通知群发（场景 4） | 订阅表 + 批量发送队列 + 限速/重试 | 自研（参考 Hindsight worker 的 `FOR UPDATE SKIP LOCKED` 轮询队列） |
| 单次/休息日/节假日定时 | 在 Orca 预设外增加 `once`、`weekends`、`monthly(day)`、`workday_cn`（中国法定节假日表） | Orca 调度骨架 + 自研日历（【V0.0.2更新】RRULE 需替换为完整实现，Orca 版本不支持 COUNT/UNTIL/MONTHLY） |
| AI 需求分解/会议 | 引擎层实现 Meeting：主持人(总控 LLM) 依次/并行向 N 个员工会话发同一议题→收集→归纳→产出 Task DAG | PentAGI generator/refiner 范式 + Orca Task/Dispatch |
| 外部上报策略（`processEscalations` 空钩子） | Escalation Classifier：自答/需决策/资源申请/风险 → 后三类走 IM，附 gate 选项按钮 | PentAGI ask 屏障 + Orca decision_gates |
| 知识库/分身 loop | Hindsight bank（每项目一个 + 每用户画像一个） | Hindsight |
| IM 侧对话记录 | `im_messages` 表关联 `route_id/session_id/resume_id`，与 Orca 式 FTS 合并检索 | 自研 + Orca schema |

---

## 7. 对 WorkFleet 的可复用清单（精确到模块）

| Orca 模块 | 复用方式 | 用作 WorkFleet 的 |
|---|---|---|
| `src/main/acp/acp-session-setup.ts`、`acp-json-rpc-peer.ts`、`acp-launch-specs.ts`、`acp-dialects/` | **移植（剥离 Electron）** | 输入端 ACP 适配器：能力协商、new/load/resume、方言扩展、表驱动注册 |
| 【V0.0.2更新】`acp-launch-specs.ts` 的 `managedRuntime` + 回收原语（#28460/#28507/#29023） | **参考** | 输入端 CLI 的“按需安装/钉版/回收旧版”管理器 |
| 【V0.0.2更新】`structured-mailbox-pointer-*.ts` 的 held 策略 | **移植策略** | 员工有待答权限时延迟总控消息；IM 侧用户有待决 gate 时合并推送 |
| 【V0.0.2更新】`src/main/orcad/orcad-instance-lock*.ts`、`serve --supervise` | **参考** | 设备端总控守护进程单实例锁与监督重启 |
| `src/main/claude/claude-agent-sdk-*`、`src/main/codex/codex-app-server-*` | **参考** | Claude Code / Codex 的非 ACP 结构化通路 |
| `src/main/runtime/orchestration/db/schema/*.ts` | **移植 schema** | 总控持久层：runs/tasks/dispatch_contexts/messages/deliveries/decision_gates |
| `src/main/runtime/orchestration/coordinator.ts` + `coordinator-escalation-triage.ts` + `coordinator-decision-gates.ts` | **移植状态机，补全 decompose 与 processEscalations** | 总控 tick 引擎 |
| `skill-guides/orchestration*.md` + `src/cli/specs/orchestration*.ts` | **协议参考** | “员工/经理 CLI 契约”：让任意 CLI 通过命令向总控 ask/worker_done |
| `src/shared/automation-schedules.ts`、`automation-cron-*.ts`；`src/main/automations/service.ts` | **移植** | 定时任务解析与 tick 调度（补 once/休息日/月） |
| `src/main/ai-vault-search/session-search-schema.ts` 等 + `src/main/ai-vault/*` collectors | **移植** | 跨 CLI 会话历史索引与按 resume ID 查询 |
| `src/main/runtime/orchestration/structured-session-lineage.ts` | **移植思路** | `/clear` 谱系：IM 发 `/clear` 后新旧 session 关联，历史可追溯 |
| `src/main/notifications/notification-delivery-service.ts` | **参考** | 多端扇出 + 去重顺序（IM 版） |
| `src/main/agent-workspace-trust*.ts`、`worker-terminal-redaction.ts` | **参考** | 远程（IM）下发指令的信任与输出脱敏 |
| Electron UI、云中继/推送、emulator/computer-use 等 | 不复用 | — |

> 文件索引：本地仓库 `/workspace/work/refs/orca`（【V0.0.2更新】HEAD `fd1c6a5`；架构与演进见 `14-Orca技术架构与实现路线.md`）；交叉引用 `03-PentAGI深度分析.md`、`05-Hindsight深度分析.md`、`01-WechatClawbot深度分析.md`（同目录）。
