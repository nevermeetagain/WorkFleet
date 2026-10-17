# 02 · Paperclip 深度分析（AideanFleet V0.0.1 参考项目）

> 分析对象：https://github.com/paperclipai/paperclip
> 分析版本：`master` @ `78b833c4958465b5e345b0e337018011b00dab72`（提交时间 2026-10-15 22:44:17 -0700 = 2026-10-16 13:44 +0800，“Dispatch routine and monitor work at saved deadlines (#16514)”）
> 本地路径：`/workspace/work/refs/paperclip`（`git clone --depth 1`，10,552 个跟踪文件，工作区约 160 MB）
> 分析日期：2026-10-16（Asia/Shanghai）
> 证据标签：`已确认` · `部分确认` · `证据不足` · `存在缺陷`
> 说明：仓库巨大（server/src/services 下 748 个文件），本报告采用**“沿需求主线追调用链”**的方式定点精读，非逐文件通读；**未安装依赖、未启动服务**（需 Node ≥ 24.11、pnpm 9、嵌入式 Postgres），所有运行时结论均为代码静态推断，凡涉及运行结果的均标注。

---

## 0. 一句话结论

Paperclip 是一个 **“AI 智能体公司操作系统”**（Node.js/TypeScript 服务端 + React 19 UI + Postgres），以 **任务（issue）+ 组织架构（reportsTo）+ 心跳运行（heartbeat run）** 为核心。它 **已原生具备 AideanFleet 输入侧最难的部分**：Claude Code / Codex（含 ACP 引擎）、Cursor、Gemini、OpenCode、OpenClaw Gateway、Hermes 等 12 个智能体适配器、会话续接（sessionParams / sessionDisplayId）、cron 定时 routine、组织树委派（天然接近“总控/职业经理人”）、`/new` 新开会话、LLM Wiki 知识库插件。

但它与 AideanFleet 的定位存在**根本性差异**：
1. **输出端（IM）只支持海外平台**：Slack / GitHub / Discord / Microsoft Teams / Telegram / Speko(语音) / AgentMail / iMessage-Photon；**无微信 ClawBot、飞书、QQ、钉钉**，且 provider 枚举被**写死在 TS 常量和 Postgres CHECK 约束**里，插件 SDK 不能扩展聊天通道。
2. **以“任务”为中心而非“消息路由”为中心**：每条 IM 对话必须绑定一个 issue、一个 endpoint 只能分配一个 agent（`assigned_agent_id NOT NULL`），没有“输入→输出”的多对多路由表；主动私信（广播）能力大部分通道为 `false`。
3. **体量与复杂度极高**：对“个人开发者统一收消息”场景偏重。

- 需求匹配度（加权估算）：**约 50%**（输入侧强、输出侧与路由模式弱，见 §2.4）
- 复用结论：**不建议整体 fork 作底座（中文 IM 缺失 + 模型不匹配 + 体量）；强烈建议复用/借鉴其“智能体适配器层（含 ACP 引擎）”、“会话续接模型”、“聊天通道能力矩阵 + 持久化投递队列”、“routine 调度”、“org-chart 委派”设计。** 另一可行路线：**Paperclip 作为 AideanFleet 的一个“上游输入端”**（AideanFleet 通过其 REST/MCP 读写 issue），由 AideanFleet 负责中文 IM。
- 许可证：**MIT**（`LICENSE`：“Copyright (c) 2025 Paperclip AI”），商用与修改友好。

---

## 1. 仓库事实（What）

### 1.1 社区与活跃度（GitHub API 2026-10-16 查询）

| 项 | 值 | 标签 |
|---|---|---|
| Stars / Forks | 102,843 / 17,215 | 已确认 |
| Open issues | 6,020 | 已确认 |
| 贡献者 | ~234（contributors API 分页 `last page=234`，per_page=1） | 部分确认（含匿名） |
| 创建 / 最近 push | 2026-03-02 / 2026-10-16 13:44（+08:00） | 已确认 |
| 最新提交 | `78b833c4`，PR #16514 → 迭代极快（PR 编号已过 1.6 万） | 已确认 |
| 发布渠道 | stable / beta / nightly / canary（`doc/CHANNELS.md`） | 已确认 |
| 许可证 | MIT | 已确认 |
| 语言 | TypeScript（服务端、UI、CLI）；`packages/paperclip-runner` 含 Rust crate | 已确认 |

结论：**头部活跃项目**，但迭代速度快 → fork 后跟进上游的合并成本高（What-if 见 §4）。

### 1.2 Monorepo 布局（`pnpm-workspace.yaml`）

| 目录 | 作用 |
|---|---|
| `server/` | Express 5 服务端（`server/package.json:97 "express": "^5.1.0"`），`src/index.ts` 入口，`routes/` 约 100 个路由文件，`services/` 748 个文件，`modules/`（分层：adapters→application→domain，`server/src/modules/README.md`） |
| `ui/` | React 19 + Vite 8 + Tailwind 4 + TanStack Query + Radix（`ui/package.json`） |
| `cli/` | `paperclipai` CLI |
| `packages/db` | Drizzle ORM + Postgres schema（`src/schema/` 169 个文件，`migrations/` 346 个） |
| `packages/shared` | 跨端类型/常量/校验（zod） |
| `packages/adapters/*` | 12 个智能体适配器：claude-local、codex-local、cursor-local、cursor-cloud、gemini-local、grok-local、kimi-local、opencode-local、pi-local、hermes、hermes-gateway、openclaw-gateway |
| `packages/adapter-utils` | 适配器公共层，含 `acpx-engine/`（ACP 执行引擎，`execute.ts` 5,680 行） |
| `packages/plugins/*` | 插件 SDK、`plugin-llm-wiki`、`plugin-workspace-diff`、沙箱提供方（e2b/daytona/modal/k8s/cloudflare…） |
| `packages/mcp-server` 等 | Paperclip 自身的 MCP 服务 |
| `skills/` | 内置技能：paperclip、paperclip-board、para-memory-files、paperclip-create-agent… |

### 1.3 关键依赖（`server/package.json`）

- ACP：`@agentclientprotocol/claude-agent-acp 0.73.0`（L47）、`@agentclientprotocol/codex-acp 1.6.2`（L48）、`acpx 0.13.1`（L84）——均在 `pnpm-workspace.yaml` 中打了补丁。
- 聊天：Vercel Chat SDK `chat 4.39.0`（L89）+ `@chat-adapter/{discord,github,slack,teams,telegram} 4.39.0`（L55-59）。
- 存储：`drizzle-orm ^0.45.2`（L95）、`embedded-postgres`（补丁）、`postgres 3.4.9`。
- 运行时：Node `>=24.11.0`（根 `package.json:108-110`），pnpm 9.15.4。
- 默认端口：`3100`（`server/src/config.ts:362 port: Number(process.env.PORT) || fileConfig?.server.port || 3100`）。

---

## 2. 需求匹配度（逐条映射）

### 2.1 核心需求

| # | 用户需求 | 结论 | 证据 / 说明 |
|---|---|---|---|
| R1-输入 | 多输入端（OpenClaw、ClaudeCode、Codex CLI、Zcode、Cursor、Coze） | **大部分支持** | `packages/adapters/` 12 个适配器；注册表 `server/src/adapters/registry.ts:255 claude_local`、`:331 codex_local`、`:836 openclaw_gateway`；另有通用 `process`、`http` 适配器（`registry.ts:136-137`）。Claude/Codex 可选 `adapterConfig.engine="acp"`（`registry.ts:186-197` 注释：旧 `acpx_local` 已退役，改为 claude_local/codex_local + engine=acp；`packages/adapters/claude-local/src/server/acp.ts:64 ClaudeExecutionEngine = "cli" \| "acp"`）。**Zcode、Coze 无内置适配器** → 需走 `process`/`http` 或外部适配器包（`server/src/adapters/plugin-loader.ts:181 loadExternalAdapterPackage`）。 |
| R1-输出 | 多 IM 输出端（飞书、微信 ClawBot、QQ、钉钉、Discord、Telegram） | **部分（仅 Discord、Telegram）** | `packages/shared/src/types/chat-channels.ts:9-18 CHAT_PROVIDERS = [slack, github, discord, microsoft-teams, telegram, speko, agentmail, imessage-photon]`；DB CHECK 约束同样写死（`packages/db/src/schema/chat_channels.ts:123,289`）。全仓 `git grep -i feishu\|wechat\|weixin\|dingtalk\|qqbot` 仅命中一份调研笔记 `doc/plans/chat-adapters/2026-09-03-chat-adapters-research-notes.md:40`（提到 Chat SDK 社区目录里有 Lark、Weixin，但**未集成**）。 |
| R2 | 后台配置管理 | **支持（形态不同）** | 完整 Web UI（`ui/src/pages/` 下 Agents、AgentDetail、CompanySettings、CompanyConnections、Routines、AgentChats、BoardChat、AdapterManager…）；适配器可声明 `getConfigSchema()` 由 UI 渲染表单（`packages/adapter-utils/src/types.ts` `ServerAdapterModule.getConfigSchema`）。但配置对象是“公司/智能体/聊天 endpoint”，**不是“输入↔输出模式”**。 |
| R3 | 管理模式（多输入→1 输出） | **部分** | 一个 chat endpoint 只能绑定一个 agent（`chat_channels.ts:50 assigned_agent_id ... notNull()`）。要实现“6 个工具→1 个微信”，在 Paperclip 语义下应：endpoint 绑定一个“经理 agent”，其余 agent 作为下属（`agents.reports_to`，`packages/db/src/schema/agents.ts:34`），结果经任务树回流再由经理发布。**多个 agent 的产出不会直接各自推到同一个 IM 会话**（发布按 conversation↔issue 绑定，见 §3.2）。 |
| R3' | 管理模式下输出端能发消息给输入端 | **支持** | IM 入站 → 创建/续接 issue → 唤醒 assigned agent（`server/src/services/chat-channels.ts:2101 issuesSvc.create(... assigneeAgentId: taskEndpoint.assignedAgentId ...)`）。 |
| R4 | 通知模式（1 输入→多输出、群发） | **弱/不支持** | 能力矩阵 `proactiveDirectMessages` 仅 `agentmail: true`，其余通道全部 `false`（`server/src/services/chat-channels/provider-catalog.ts:17-105`）；`email-channels.ts:110` 也为 true。即：**除邮件外不能主动给“没先发过消息的用户”推送**；也没有订阅者列表/批量投递模型。同一 agent 可以被多个 endpoint 绑定（`chat_endpoints_agent_idx` 是普通 index 非 unique），但一次 run 的输出只发到该 issue 绑定的 conversation。 |
| R5 | 团队模式（多对多：产品线 A→微信、B→QQ、公司→飞书） | **部分（概念可映射，通道缺失）** | 多公司（Multi-Organization，README “One deployment, many organizations”）/ 多项目 + 多 endpoint 可以表达“产品线→通道”的分组；`chat_agent_routes`（`chat_channels.ts:706-746`）支持 endpoint 之间的 agent 路由（`trigger_mode` 默认 `explicit_mention`、`max_hops 1..8`）。但中文 IM 缺失，示例中的 3 个通道（微信/QQ/飞书）**一个都没有**。 |

### 2.2 扩展需求

| # | 需求 | 结论 | 证据 |
|---|---|---|---|
| E1 | 定时任务（一次/工作日/休息日/每日/每周/每月） | **大部分支持** | `routines` + `routine_triggers`（`packages/db/src/schema/routines.ts:23,106`）：`cron_expression` + `timezone`（L118-119）、`concurrency_policy`（默认 `coalesce_if_active`）、`catch_up_policy`（默认 `skip_missed`，可 `enqueue_missed_with_cap`）；触发类型 `ROUTINE_TRIGGER_KINDS = ["schedule","webhook","api"]`（`packages/shared/src/constants.ts:648`）。调度 tick：`server/src/index.ts:1889 tickRoutines → routines.tickScheduledTriggers`（`server/src/services/routines.ts:3199`），自研 5 段 cron 解析（`server/src/services/cron.ts`）。**不支持**：“只运行一次”的原生触发（无 once 类型，可用 `api` 触发变通 → 部分确认）；**中国法定节假日/调休**（cron 只能 `1-5`）。routine 产物是**给 agent 的任务**，不是直接群发文本。 |
| E2 | `/clear` 新开对话 | **支持（指令名不同）** | Telegram/Discord/Slack 支持 `/new`、`/close`、`/status`（`server/src/services/chat-channels/telegram/commands.ts:36-38,118-121`；`chat-channels.ts:1052-1055` 注释）。实现：线性会话（DM 等）`session_generation + 1` 并新建 issue（`chat-channels.ts:2098-2131`；`chat_conversations.session_generation` `chat_channels.ts:382`），旧 issue 保留。另有 `POST /agents/:id/runtime-state/reset-session`（`server/src/routes/agents.ts:4180`）重置 agent 原生会话。 |
| E3 | 两端对话记录查看（按 session/resume ID） | **大部分支持** | `agent_task_sessions`（`packages/db/src/schema/agent_task_sessions.ts:17-60`）：`(company, agent, adapter_type, task_key)` 唯一，存 `session_params_json` 与 `session_display_id`（L23-25，即 Claude/Codex 的 resume ID 展示值）；`heartbeat_runs.session_id_before/after`、`native_session_id`（`heartbeat_runs.ts:63,72-73`）；`GET /agents/:id/task-sessions`（`routes/agents.ts:4164`）。IM 侧：`chat_conversations`、`chat_deliveries`、`chat_publications`、`chat_message_links`。**“按 resume ID 反查”的专用查询端点** → `证据不足`（字段存在，未找到按 session_display_id 检索的路由）。 |
| E4 | 身份数据采集优化 / 分身自动更新 loop | **部分** | `agent_instruction_revisions/heads/working_copies`（`packages/db/src/schema/agent_instruction_revisions.ts:16,59,89`，指令版本化）；README 宣称“active learning loops、performance reviews、skill version history”；`decision-training` 路由存在。**“自动采集用户身份→更新分身”闭环未找到明确实现** → `证据不足`。注意 `doc/agent-personas.md` 的 persona 指**头像视觉形象**，不是人格画像。 |
| E5 | 知识库（项目设计、目录结构图谱、上下文记忆） | **部分支持** | `packages/plugins/plugin-llm-wiki`（README：raw/ + wiki/ 本地文件夹、`Wiki Maintainer` 托管 agent、托管 routine 做更新/lint/索引、wiki 搜索/读写/反链工具、按项目 `standup.md`）；`documents`/`document_revisions` 表；`skills/para-memory-files`（PARA 文件式记忆：知识图谱 / 每日笔记 / 隐性知识）。**无向量检索/代码目录图谱** → `证据不足`。 |
| E6 | 总控模式（职业经理人：开会、分派、把关、汇报） | **部分支持（最接近）** | 组织架构：`agents.reports_to` 自引用（`agents.ts:34`）、`role`、`title`；README “Delegation flows up and down the org chart”；`skills/paperclip/SKILL.md:160,224,269` 规定通过子 issue（`parentId/goalId`）委派、不得忙轮询；审批 `approvals`、`issue_approvals`；`issue_plan_decompositions`（计划拆解）；Primary agent（`server/src/services/primary-agent.ts` 每个用户可设一个首选 agent）。**缺**：① “多 agent 会议/角色扮演讨论”机制（`证据不足`，未找到会议协议）；② “所有输入端输出**强制**先经总控把关再发 IM”的过滤管线（Paperclip 中 agent 可直接在其 issue 线程发布）。 |
| E7 | 总控自定义模型、skill 配置 | **支持** | 每个 agent 独立 `adapter_type` + `adapter_config`（`agents.ts:36-37`），适配器 `listModels/refreshModels/detectModel`、`listSkills/syncSkills`（`types.ts:504-` `ServerAdapterModule`）；公司级技能 `company_skills`、`company_skill_sources`、`company_skill_policies`。 |
| E8 | 与总控随时对话、不影响执行中的任务 | **部分支持** | `chat_endpoints.concurrency_policy ∈ {burst, queue, debounce, drop, concurrent}`（`chat_channels.ts:78,135`；`shared/types/chat-channels.ts:35-41`），默认 `queue`；Board Concierge Chat（`server/src/routes/board-chat.ts`：spawn `claude` CLI（L255）+ SSE，持久化到 “Board Operations” issue）；Fast responses（`doc/fast-responses.md`：用直连模型在 3 秒内给人类回合一个确认回执，同时 agent 继续正常执行，默认关闭、实验特性）。**“与经理对话不打断其正在执行的 run”** 的语义需运行验证 → `部分确认`。 |
| — | 总控“必须运行在设备上” | **支持** | `claude_local`/`codex_local` 等本地进程适配器；部署模式 `local_trusted`/`authenticated`（`doc/DEPLOYMENT-MODES.md:31-32`）；也支持远程沙箱（e2b/daytona/k8s…）。 |

### 2.3 四个场景

| 场景 | 结论 | 说明 |
|---|---|---|
| S1 三项目、6 个开发工具 → 微信 ClawBot 统一接收 | **部分** | 6 个工具中 Claude Code / Codex / Cursor / OpenClaw 可直接作为 agent；三项目→`projects`；统一入口可用“经理 agent + endpoint”。**微信通道缺失**——必须自研 WeChat provider（需改 `CHAT_PROVIDERS`、DB CHECK、能力矩阵、runtime），或由 AideanFleet 外挂。 |
| S2 飞书数据管理：推广/运营/销售 3 个分析 agent → 数据部门 + 老板 | **部分** | 3 个 agent + routine 可做；“同一结果扇出给 2 个接收方”无原生模型（发布绑定单 conversation），且无飞书。 |
| S3 主项目 + 子项目，一个管理入口，总控统一开发 | **支持度最高** | 这正是 Paperclip 的主场景：goal → project → issue 树、CEO/CTO/工程师 org chart、审批、预算、工作区（git worktree）。账号通用→多项目同公司。 |
| S4 大量用户订阅，每日 9 点推送 AI 资讯 | **不支持** | routine 可每天 9 点让 agent 生成资讯；但**无订阅者模型、主动私信能力 false、无大规模扇出投递**。Paperclip 面向“公司内部成员”而非 C 端大量订阅用户。 |

### 2.4 加权匹配估算（与 01 报告同一权重）

| 维度（权重） | 得分 | 加权 |
|---|---|---|
| 多输入端（编码智能体/ACP）25% | 90 | 22.5 |
| 多输出端 IM 20% | 25（Discord/Telegram 有，中文 IM 0） | 5 |
| 三种路由模式 20% | 30 | 6 |
| 后台配置 10% | 80 | 8 |
| 定时任务 5% | 75 | 3.75 |
| /clear 与会话记录 5% | 85 | 4.25 |
| 总控模式 10% | 55 | 5.5 |
| 知识库/画像 loop 5% | 45 | 2.25 |
| **合计** | | **≈ 57%**（保守口径扣除“未运行验证”折扣后按 **约 50%** 报告） |

> 权重为分析者对需求的主观拆分；分值基于静态代码证据，未经运行验证。

---

## 3. 全维度分析

### 3.1 前端
- React 19 + Vite 8 + Tailwind 4 + Radix/shadcn 风格组件（`ui/components.json`）+ TanStack Query；i18n 目录 `ui/src/i18n`（中文支持程度 `证据不足`）；Storybook；移动端预览脚本 `dev:mobile`（README 宣称“manage from your phone”）。
- 页面：Agents/AgentDetail（含实时 run、历史、指令版本、工具）、AgentChat(s)、BoardChat、Routines/RoutineDetail、Approvals、Cases、CompanySkills、CompanyConnections、AdapterManager、Artifacts 等。
- 适配器 UI 可插拔：每个适配器包有 `src/ui/`（如 `packages/adapters/claude-local/src/ui/build-config.ts`、`parse-stdout.ts`），声明式配置表单 `getConfigSchema`。
- 对 AideanFleet：**“路由配置（输入×输出矩阵）”页面需自研**；Agent 管理、Run 转录、Routine 编辑器可大量参考。

### 3.2 后端（核心调用链，已确认为静态追踪）

**A. IM 入站 → 智能体执行 → IM 回发**
1. 通道运行时：Vercel Chat SDK 适配器（`server/src/services/chat-sdk-runtime.ts` 3,301 行）收 webhook/长连接 → `chatChannelService.handleWebhook`（`chat-channels.ts:2868`）/ `handleSdkMessage`（L2599）。
2. 持久化入站：`chat_deliveries` 账本（`chat-channels/inbound/delivery-ledger.ts`），由 `DELIVERY_QUEUES.chatInbound` 队列驱动（`server/src/services/delivery-work-notifications.ts:3-31`，基于 Postgres 的 `signalDatabaseWork/subscribeDatabaseWork`）。
3. `processMessage`（`chat-channels.ts:1377`）：过滤 bot/self/system 消息 → 身份关联与授权（`inbound/authorization.ts`、`identity-links.ts`）→ 若无会话则在事务中 `issuesSvc.create`（L2101，`originKind:"chat_channel"`、`idempotencyKey: chat:{endpoint}:{thread}:{generation}`）并插入 `chat_conversations`（L2123-2131）。
4. 唤醒：`createInboundWakeups` → `options.heartbeat.wakeup(...)`（L1203）→ heartbeat 队列 `enqueueWakeup`（`heartbeat.ts:1273`）。
5. 执行：heartbeat run → `session-preparation.ts`（恢复 `previousSessionParams`，或用 `getFreshSessionHandoff` 生成有界历史交接，L193-219）→ `runtime-execution.ts:796 adapter.execute({...})` → 适配器（如 claude_local，engine=cli 或 acp）。
6. 回发：run 事件 → `chat-run-publications.ts` → `chat_publications` → `DELIVERY_QUEUES.chatPublications` worker（`chat-channels/publications/worker.ts`）→ 通道 SDK 发布（支持编辑消息合并 queued/working/final 状态，`provider-catalog.ts:71-75` 注释）。

**B. 定时 routine**
`server/src/index.ts:1889 tickRoutines` → `routines.tickScheduledTriggers(now)`（`routines.ts:3199`）：查询 `kind='schedule' AND enabled AND nextRunAt<=now` → 项目暂停则抑制 → 按 catch-up 策略计算下一次 → 乐观更新 `nextRunAt` 抢占 → 派发 routine run（创建 issue 给 `assignee_agent_id`）。`scheduled-work.ts` 把 timer/routine 注册到投递协调器，按“下一截止时间”唤醒（本次最新提交 #16514 即“在保存的截止时间派发 routine”）。

**C. 适配器接口**（`packages/adapter-utils/src/types.ts`）
- `ServerAdapterModule`（L504）：`type`、`execute(ctx)`、`testEnvironment`、`acp?`、`listSkills/syncSkills`、`sessionCodec`、`sessionManagement`、`models/listModels/refreshModels/detectModel`、`getConfigSchema`、`getQuotaWindows`、`onHireApproved` 等。
- `AdapterRuntime`（L19-26）：`sessionId`(legacy)、`sessionParams`、`sessionDisplayId`、`taskKey`。
- `AdapterExecutionContext`（L237-）：`runId`、`agent`、`runtime`、`config`、`context`、`signal`（取消）、`getFreshSessionHandoff`、`executionTarget`（本地/远程/沙箱）、`runtimeMcp/runtimeTools`、`onLog/onEvent/onUsage`。
- 外部适配器：`plugin-loader.ts:181 loadExternalAdapterPackage`、`:221 reloadExternalAdapter`；`adapter-plugin.md` 记录 `registerServerAdapter/unregisterServerAdapter`。
→ **这是 AideanFleet 输入端抽象最值得借鉴的接口**。

### 3.3 数据（Postgres / Drizzle，节选与 AideanFleet 相关的表）

| 表 | 关键字段 | 对 AideanFleet 的意义 |
|---|---|---|
| `agents` | company_id、name、role、title、**reports_to**、adapter_type、adapter_config、runtime_config、budget、status、lifecycle_* | “输入端实例”+ 组织树 |
| `agent_task_sessions` | (company, agent, adapter_type, task_key) 唯一、session_params_json、**session_display_id**、last_run_id、goal_* | “resume ID” 持久化 |
| `heartbeat_runs` / `heartbeat_run_events` | session_id_before/after、native_session_id、事件流 | 单次执行与转录 |
| `chat_endpoints` | provider、**assigned_agent_id NOT NULL**、publication_mode(automatic/explicit)、external_execution_policy、allow_direct_messages、require_at_mention、allow_group_chats、concurrency_policy、capabilities(jsonb)、communication_instructions、setup、status | “输出端实例”，但 1 endpoint = 1 agent |
| `chat_conversations` | endpoint_id、**issue_id NOT NULL**、external_conversation_id/thread_id、**session_generation**、is_direct_message、state | IM 会话 ↔ 任务 |
| `chat_deliveries` / `chat_publications` / `chat_message_links` / `chat_actions` | 入站账本 / 出站发布 / 平台消息 ID 映射 / 交互动作 | 可靠投递、幂等 |
| `chat_agent_routes` | source_endpoint_id → destination_endpoint_id、enabled、trigger_mode、max_hops(1-8) | 通道间 agent 路由（接近“团队模式”的一小部分） |
| `chat_identity_links` / `chat_external_principals` | IM 用户 ↔ Paperclip 用户 | 多用户身份 |
| `routines` / `routine_revisions` / `routine_triggers` / `routine_runs` | cron_expression、timezone、concurrency/catch-up 策略、idempotency_key | 定时任务 |
| `issues` / `issue_comments` / `issue_documents` / `issue_plan_decompositions` / `approvals` | 任务树、对话、计划、审批 | 总控工作流 |
| `documents` / `document_revisions` | 文档与版本 | 知识库 |
| `agent_instruction_revisions` 等 | 指令（人格/system prompt）版本 | 分身迭代基础 |
| `company_skills*` | 技能及来源/策略 | skill 配置 |
| `cost_events` / budget | 成本 | 资源控制 |

多租户：几乎所有表带 `company_id` 并用复合外键 `(company_id, id)` 防跨公司引用（如 `chat_conversations_company_issue_fk`）。

### 3.4 交互
- IM 内：DM 直接开任务；群组需 `/task@bot` 或 @mention（`telegram/commands.ts:118`）；`/new /close /status`；问题表单/按钮（`chat-question-forms.ts`、Discord/Slack modal）；回执表情（receipt reactions）；流式（Slack/Telegram `nativeStreaming:true`）。
- Web：任务看板、Agent 实时运行、Board Concierge Chat（SSE）。
- 智能体侧：通过 Paperclip skill + 控制面 API/MCP 自主创建子任务、委派、请求人类输入。

### 3.5 逻辑
- **核心心智模型**：“消息 = 任务的一个回合”。IM 消息不是被“路由到某个工具”，而是“变成分配给某个 agent 的 issue”。这对 S3（总控开发）是优势，对 S1/S4（多源汇聚通知、群发）是劣势。
- 并发策略：endpoint 级 `burst/queue/debounce/drop/concurrent`；routine 级 `coalesce_if_active`；会话代数 `session_generation` 保证 `/new` 后旧消息不污染新任务（`chat-channels.ts:1834` 对“早于 close/new 的消息”给出提示）。
- 信任分级：低信任预设 `LOW_TRUST_REVIEW_PRESET`（`chat-channels.ts:2259`，`doc/LOW-TRUST-PRESETS.md`），外部未关联用户执行策略 `external_execution_policy` 默认 `restricted`。

### 3.6 组件（可借鉴清单）

| 组件 | 位置 | 借鉴价值 |
|---|---|---|
| 适配器接口 + 注册表 + 外部包加载 | `adapter-utils/src/types.ts`、`server/src/adapters/registry.ts`、`plugin-loader.ts` | ★★★★★ |
| ACP 执行引擎 | `adapter-utils/src/acpx-engine/*`、`claude-local/src/server/acp.ts`、`codex-local/src/server/acp.ts` | ★★★★★（MIT，可直接依赖 `acpx` 与官方 ACP 包） |
| 会话续接/交接 | `heartbeat/session-preparation.ts`、`adapter-utils/src/session-compaction.ts` | ★★★★ |
| 通道能力矩阵 | `chat-channels/provider-catalog.ts` | ★★★★（AideanFleet 通道抽象直接沿用字段集） |
| 持久化投递队列（Postgres NOTIFY 式） | `delivery-work-notifications.ts`、`chat-channels/publications/*`、`inbound/delivery-ledger.ts` | ★★★★（思路；实现与其 schema 深耦合） |
| cron 解析 + 时区 + catch-up | `services/cron.ts`、`routines.ts:3199-` | ★★★★ |
| org-chart 委派 + 审批 | `agents.reports_to`、`approvals`、`skills/paperclip` | ★★★★（总控模式蓝本） |
| LLM Wiki 插件 | `packages/plugins/plugin-llm-wiki` | ★★★ |
| PARA 记忆技能 | `skills/para-memory-files` | ★★★ |
| Fast responses（先回执后执行） | `services/fast-responses.ts`、`doc/fast-responses.md` | ★★★（“随时对话不影响任务”的一种实现） |

### 3.7 复用
- **路线 1：整体 fork 并补中文 IM** — 需改：`CHAT_PROVIDERS` 常量、DB CHECK 约束 + 迁移、能力矩阵、`chat-sdk-runtime` 中按 provider 的分支（Telegram/Discord/Teams 均有大量专属文件：`chat-telegram-*.ts`、`chat-discord-*.ts` 数十个），并**持续跟随日更上游**。成本高、冲突多。不推荐。
- **路线 2：Paperclip 作为 AideanFleet 的上游“输入端”** — AideanFleet 通过 Paperclip REST/MCP（`packages/mcp-server`、`routes/public-mcp.ts`）订阅 issue/run 事件并转发到微信/飞书/QQ/钉钉，反向把 IM 消息写成 issue comment。优点：零侵入、享受上游迭代。缺点：两套系统、两份身份。**推荐作为“总控/团队模式”的可选集成**。
- **路线 3：选择性移植/依赖** — 直接依赖 `acpx`、`@agentclientprotocol/*` 包；按 MIT 移植适配器接口、cron、能力矩阵、会话模型设计到 AideanFleet 自研内核。**推荐作为 AideanFleet 主路线**。

### 3.8 性能
- 设计面：Postgres 事务 + 行锁（`for("update")`）+ 幂等键 + 持久化队列，正确性优先；heartbeat 有 watchdog（`modules/active-run-watchdog`）、唤醒节流（`issue-rewake-throttle.ts`）、预算闸门。有 `perf:workspace-admission` 基准脚本、`IssueChatLongThreadPerf.tsx` 长线程性能实验页。
- 风险：单服务进程内承载 748 个服务文件的复杂度；每次 IM 消息都经 issue 创建 + 权限双重校验（`assertChatTaskCreationAccess` 调两次，`chat-channels.ts:2086-2097`）→ 对“高频通知流/大规模群发”是重路径。吞吐数据 → `证据不足`（未运行）。

### 3.9 配置
- `server/src/config.ts`（环境变量 + 配置文件 `config-file.ts`）：`PORT`（默认 3100）、`DATABASE_URL`（缺省用嵌入式 Postgres）、部署模式、密钥提供方（`secrets/`，支持 AWS 等，`doc/SECRETS-AWS-PROVIDER.md`）。
- 运行时配置大多存 DB 并经 UI 编辑（agent adapter_config、endpoint 设置、routine）。
- 约束提醒：AideanFleet 要求 Aidean=3000、AideanBot=3333；Paperclip 默认 3100 不冲突，若并存需显式配置 → 无冲突（已确认默认值）。

### 3.10 知识库
- `plugin-llm-wiki`：本地文件夹（raw/、wiki/、AGENTS.md、IDEA.md、index.md、log.md）+ 插件 DB 命名空间（实例、源、页面、操作、查询会话），托管 Wiki Maintainer agent 与 routine；Paperclip 事件摄取默认关闭；附件仅元数据（安全闸门 Phase 5）。
- `documents` 系列表 + `issue_documents`；`skills/para-memory-files`。
- 缺：向量语义检索、代码仓目录结构图谱 → 需借鉴 Hindsight 等（`待其他员工完成`）。

### 3.11 响应
- 流式：Slack/Telegram 原生流式；Teams 因 durable ingress 改为“编辑消息合并状态”（`provider-catalog.ts:71-75`）。
- 快速回执：Fast responses（3 秒 admission deadline，`doc/SPEC-implementation.md:2234`），默认关闭。
- 回执表情（receipt reactions）表明“已收到”。

### 3.12 存储
- Postgres（嵌入式或外部），`db:backup` 脚本、实例数据库备份路由（`routes/instance-database-backups.ts`）；附件/资产 `server/src/storage`；git worktree 工作区。
- 迁移 346 个、带迁移安全检查（`packages/db/src/check-migration-safety.ts`）。

### 3.13 资源
- Node ≥24.11、pnpm、嵌入式 Postgres、可选 Rust runner；源码 160 MB（不含 node_modules）。个人单机可跑（README 有 quickstart/npx），但相对 AideanFleet“轻量网关”的预期偏重。实际内存/CPU → `证据不足`（未运行）。

### 3.14 安全
- 认证：better-auth（迁移文件名 `better-auth-account-issuer-migration.test.ts`）、board API key、agent API key / JWT（`agent-auth-jwt.ts`）、部署模式 `local_trusted` / `authenticated`（private/public）。
- 多租户隔离：复合外键 + 查询必带 company 谓词（`chat-channel-binding.ts:11-15` 注释明确防“跨公司发现”）。
- 密钥：`company_secrets*` 版本化、提供方配置、日志脱敏（`log-redaction.ts`、`redaction.ts`）。
- IM 外部人员：`allow_unlinked_people`、`external_execution_policy=restricted`、低信任预设、身份链接。
- 沙箱：本地进程文件系统/网络范围（`local-process-sandbox`）、远程沙箱提供方。
- 安全姿态徽章 Superagent（README），`SECURITY.md` 存在。
- 结论：**安全设计远强于 AideanFleet 起步所需**，可作为合规参考。

### 3.15 许可证
- MIT（`LICENSE`）。可自由使用/修改/商用，保留版权声明即可。注意其依赖的打补丁第三方包（`patches/`）各自许可证 → `证据不足`（未逐个核查）。

### 3.16 社区活跃度
- 10 万+ star、1.7 万 fork、约 234 贡献者、PR 编号 >16,500、当天仍有提交、四个发布渠道。生态有 Discord 社区与官方文档站 docs.paperclip.ing。

---

## 4. 5W1H 拆解（第一轮）

- **What**：一个面向“智能体公司”的编排平台；已实现多智能体适配（含 ACP）、任务树、组织架构、审批、预算、routine、海外 IM 通道、知识 wiki 插件。缺中文 IM、消息路由矩阵、订阅群发、会议式协作、强制总控把关。全部结论来自静态代码；无运行证据。
- **Why**：其产品定义是“If OpenClaw is an employee, Paperclip is the company”（README），目标用户是管理“自治 AI 组织”，因此一切围绕 issue/goal，IM 只是“任务入口与回报通道”，不是“消息总线”。AideanFleet 的痛点是“一个微信收所有工具消息、不再反复扫码”，属于**通道复用/消息路由**问题——这是两者匹配度上限的根本原因。
- **Where/When**：可借鉴代码集中在 `packages/adapter-utils`、`packages/adapters/*`、`server/src/adapters/`、`server/src/services/{cron,routines}.ts`、`chat-channels/provider-catalog.ts`、`packages/db/src/schema/{agents,agent_task_sessions,chat_channels,routines}.ts`。应在 AideanFleet“输入端适配器层”与“会话/调度层”设计阶段（先于编码）引用。
- **Who**：Paperclip AI 团队与社区；AideanFleet 方需要：输入端负责人（参考适配器）、通道负责人（中文 IM 自研）、总控负责人（参考 org chart/委派）。
- **How**：① 直接依赖 `acpx` + 官方 ACP 包实现 Claude Code / Codex 输入；② 移植 `ServerAdapterModule` 形状定义 AideanFleet `InputAdapter`；③ 沿用能力矩阵定义 `ChannelAdapter`；④ 自研 `Route` 表（mode: manage/notify/team/control）；⑤ 可选“Paperclip 桥接输入端”。
- **What if**：
  - 上游日更：fork 路线会持续冲突 → 选“依赖包 + 设计借鉴”或“桥接”。
  - ACP 包版本变化：Paperclip 自己对 `acpx@0.12/0.13`、`claude-agent-acp@0.73.0`、`codex-acp@1.6.2` 打了补丁（`pnpm-workspace.yaml patchedDependencies`）→ 说明官方包尚不稳定，AideanFleet 依赖时需锁版本并准备补丁（已确认存在补丁；补丁内容未审阅 → 证据不足）。
  - 依赖服务不可用（Postgres）：Paperclip 有嵌入式 Postgres supervisor（`server/src/embedded-postgres-supervisor.ts`），AideanFleet 若采用 SQLite 则需另设计队列。
  - 端口：默认 3100，与 3000/3333 不冲突。
  - 若用户实际只需要 S1/S4（汇聚+群发），Paperclip 的价值显著下降；若主要做 S3（总控开发），Paperclip 可能“直接可用 + 外挂微信桥”。

## 5. 苏格拉底追问 + 双向钢人论证

**结论 A：“Paperclip 不适合直接作为 AideanFleet 底座。”**
- 凭什么：中文 IM 0 个（`CHAT_PROVIDERS` + DB CHECK）；endpoint↔agent 1:1（`assigned_agent_id NOT NULL`）；conversation↔issue 必绑（`issue_id NOT NULL`）；主动私信能力几乎全为 false。
- 支持论证：以上均为 schema 级硬约束，改动牵涉迁移与大量 provider 专属代码；S4 群发与其“公司成员”模型冲突。
- 反对论证（最强）：Paperclip 已覆盖输入侧 90%、总控 55%，而这些恰是最难自研的部分；中文 IM 只是“再加几个 provider”；10 万 star 社区可能很快官方支持 Lark/Weixin（调研笔记 `2026-09-03-chat-adapters-research-notes.md:40` 已列入目录）；“管理模式=经理 agent 绑定一个微信 endpoint”在语义上可行。
- 裁决：反对意见**部分成立**——对 S3 场景 Paperclip 几乎可直接用。但 AideanFleet 的首要痛点（S1：多工具→一个微信、免反复扫码）与 S4（群发）在 Paperclip 中需要**改核心模型**而非加插件（插件 SDK 无聊天 provider 扩展点：`packages/plugins/sdk/src` grep `chatProvider/registerChat` 无结果）。**结论 A 成立（部分确认，因未运行验证）**；同时保留“Paperclip 作为 S3 总控上游”的集成路线。

**结论 B：“Paperclip 的适配器层是 AideanFleet 输入端的最佳参考。”**
- 证据：12 个适配器、统一 `ServerAdapterModule`、ACP 引擎、会话 codec、模型发现、技能同步、外部包加载。
- 反对：适配器与 Paperclip 运行时（heartbeat、workspace、sandbox、budget、runtime tools/MCP）耦合深（`AdapterExecutionContext` 字段大量 Paperclip 专属），直接复用代码困难；ACP 引擎 5,680 行复杂度高。
- 裁决：**复用“接口形状 + 依赖相同的 ACP 官方包”，不复用实现代码**。结论 B 成立（已确认接口存在；可移植性 部分确认）。

**结论 C：“Paperclip 的 org chart 可作为总控模式蓝本。”**
- 证据：`reports_to`、委派规则（skill）、审批、计划拆解、primary agent。
- 反对：需求中的“会议：各输入端扮演员工讨论、总控统一意见”与“所有输出必经总控把关”在代码中未找到对应机制；Paperclip 的委派是异步任务树，不是同步讨论。
- 裁决：**部分确认**。总控的“分派与汇报”可借鉴，“会议”与“出口把关过滤器”需自研。

**结论 D：“/new 可满足 /clear 需求。”**
- 证据：`telegram/commands.ts:36-38`、`session_generation`、`reset-session` 路由。
- 反对：`/new` 新建 issue，等价于“新任务 + 新会话”，不完全等于“对 ClaudeCode 原生会话 /clear”（是否同时重置 agent_task_session 取决于 task_key 是否变化，推断 issue 变化即 task_key 变化 → `部分确认`）。
- 裁决：语义基本满足，指令名可在 AideanFleet 中映射 `/clear → new session`。

## 6. 缺陷 / 风险清单（相对 AideanFleet 需求）

| # | 问题 | 证据 | 标签 |
|---|---|---|---|
| 6.1 | 中文 IM（微信/飞书/QQ/钉钉）全无，且 provider 写死于常量与 DB CHECK | `shared/types/chat-channels.ts:9-18`；`chat_channels.ts:123,289` | 已确认 |
| 6.2 | 插件 SDK 不能新增聊天通道 | `packages/plugins/sdk/src` 无相关导出 | 部分确认 |
| 6.3 | 1 endpoint = 1 agent；对话必须绑定 issue | `chat_channels.ts:50,374` | 已确认 |
| 6.4 | 主动私信/群发能力缺失（仅邮件类 true） | `provider-catalog.ts:17-105`；`email-channels.ts:110` | 已确认 |
| 6.5 | 无一次性定时、无节假日日历 | `constants.ts:648`；`cron.ts` 5 段 | 已确认/部分确认（一次性） |
| 6.6 | 依赖的 ACP 包需打补丁，说明上游不稳定 | `pnpm-workspace.yaml patchedDependencies` | 已确认 |
| 6.7 | 体量巨大、日更，fork 维护成本高 | 10,552 文件、PR #16514 | 已确认 |
| 6.8 | 运行时行为（吞吐、资源、流式效果）未验证 | 未安装运行 | 证据不足 |
| 6.9 | 会议式多 agent 讨论、强制总控出口把关未找到 | grep 未命中 | 证据不足 |
| 6.10 | Zcode、Coze 无内置适配器 | `packages/adapters/` 列表 | 已确认 |

## 7. 差距 → 补齐方案

| 差距 | 补齐方案 | 借鉴来源 |
|---|---|---|
| 微信 ClawBot 通道 | 自研 `WeChatILinkChannel`，按 iLink 五接口 + 扫码状态机 + supersede 规则 | **WechatClawbot** `src/wechat_clawbot/wechat/*`、`app.py:131-229`（需确认授权或重写） |
| 飞书 / 钉钉 / QQ 通道 | 自研 ChannelAdapter（官方开放平台 SDK）；或评估 Chat SDK 社区目录中的 Lark 适配器 | 调研笔记 `doc/plans/chat-adapters/...:40`（`证据不足`，需另行调研） |
| Discord / Telegram | 直接使用 Vercel `chat` SDK + `@chat-adapter/*`（Paperclip 同款依赖，注意其补丁） | Paperclip `server/package.json:55-59,89` |
| 输入↔输出路由矩阵（管理/通知/团队/总控 4 模式） | 自研 `routes(input_id|group, channel_endpoint_id[], mode, filters, tag_prefix)` + 消息总线；`max_hops` 防环 | 自研；参考 `chat_agent_routes` |
| 通知模式群发 / S4 订阅 | 订阅表 + 批次投递 + 每通道限速 + 重试 + 退订 | 自研；投递可靠性参考 Paperclip delivery ledger |
| 输入端适配 | 定义 `InputAdapter{type, start/execute, cancel, session{new,resume,list}, models, skills, capabilities}`；Claude/Codex 依赖 `@agentclientprotocol/*` + `acpx`；Cursor/OpenClaw/Gemini 参考对应包；Zcode/Coze 走 process/http | Paperclip `adapter-utils/src/types.ts:504`、`packages/adapters/*` |
| /clear | `/clear` → 新 session_generation + ACP `session/new`；旧会话可查 | Paperclip `session_generation`、`reset-session` |
| 会话记录按 resume ID 查询 | append-only 消息表 + `(input_id, native_session_id)` 索引 + 查询 API | Paperclip `agent_task_sessions.session_display_id`、`heartbeat_runs.session_id_*` |
| 定时任务 | 持久化调度 + 时区 + catch-up + once 类型 + 节假日日历 | Paperclip `routines`/`cron.ts`；节假日库需另调研 |
| 总控模式 | 设备端 manager agent（自定义模型/skill）+ 委派任务树 + **出口把关过滤器**（分级：自动答复 / 升级到人）+ **会议协议**（多轮 round-robin 讨论 → 总控汇总） | Paperclip org chart、approvals、fast responses；会议协议自研 |
| 随时与总控对话 | 总控对话通道独立于任务执行队列（concurrency=concurrent）+ 快速回执 | Paperclip `concurrency_policy`、fast responses |
| 知识库 | LLM Wiki 思路 + 向量检索 + 目录图谱 | Paperclip `plugin-llm-wiki`、`para-memory-files`；Hindsight 等（`待其他员工完成`） |
| 分身 loop | 指令版本化 + 定期 routine 汇总用户偏好 → 生成新版本 → 人工审批 | Paperclip `agent_instruction_revisions` + approvals |

## 8. 最终判断（第四轮重构）

1. **明确结论**：Paperclip 是本次两个参考项目中**与 AideanFleet 最接近、价值最高**的一个（匹配约 50%），尤其输入侧（多智能体 + ACP）与总控雏形；但 **不建议直接 fork 作为底座**，建议采用 **“自研轻量路由内核 + 依赖 ACP 官方包 + 移植 Paperclip 接口/模型设计”**，并把 **Paperclip 作为可选上游（S3 总控开发场景）** 进行桥接。
2. **依据**：§2 映射、§3.2 调用链、§3.3 schema 硬约束、§5 论证。
3. **代码证据**：`packages/shared/src/types/chat-channels.ts:9-18`；`packages/db/src/schema/chat_channels.ts:50,123,374,382,706`；`provider-catalog.ts:17-105`；`chat-channels.ts:1377,2098-2131`；`adapter-utils/src/types.ts:19-26,237,504`；`registry.ts:186-197,255,331,836`；`agents.ts:34`；`agent_task_sessions.ts:23-25`；`routines.ts(schema):118-119`；`services/routines.ts:3199`；`index.ts:1889`；`telegram/commands.ts:36-38`；`routes/agents.ts:4164,4180`；`config.ts:362`。
4. **命令证据**：`git log -1`（SHA/日期）；GitHub API（stars/forks/license/pushed_at）；`git grep` 中文 IM 关键字仅命中调研笔记；目录/文件计数。
5. **成立前提**：基于 `78b833c4`；上游未在近期加入中文 IM / 路由矩阵。
6. **局限**：未运行、未压测；仅定点精读与需求相关的约 30 个文件；UI 中文化、i18n 未核实。
7. **未验证**：E3 按 resume ID 反查端点；E4 自动画像 loop；E8 并发对话语义；ACP 补丁内容；插件 SDK 能否间接扩展通道。
8. **风险**：上游极速迭代导致借鉴的接口快速过时；ACP 包不稳定；若 AideanFleet 将来需要组织级治理，自研会重复造轮子。
9. **下一步**：① 在本地以 Node 24 起一套 Paperclip，实测 Claude Code（engine=acp）+ Telegram endpoint 的端到端回路与资源占用；② 用 `@agentclientprotocol/claude-agent-acp`、`codex-acp`、`acpx` 做 AideanFleet 输入端 PoC；③ 与 WechatClawbot iLink 适配器拼接，验证 S1 最小闭环；④ 评估“Paperclip 桥接输入端”的 API 面（`packages/mcp-server`、`routes/public-mcp.ts`）。
10. **是否进入下一阶段**：**允许**带着“借鉴清单 + 桥接备选”进入 AideanFleet 架构设计；**不允许**以“fork Paperclip”作为既定方案进入开发，除非 PoC 证明中文 IM 改造成本可控。
