# 01 · ACP（Agent Client Protocol）协议深度分析

> 【V0.0.2更新】2026-10-17：ACP 规范发布 **v1.12.0 + schema-v1.26.0 + schema-v2.0.0-alpha.9**（2026-10-16，HEAD `e7dac67`），v1 稳定方法集未见破坏性变更；`claude-agent-acp` **v0.93.0**（升级 ACP SDK 1.9.0、新增 `/remote-control`、修复 resume 子代理与 fork 列表）；`codex-acp` 最新发布 v2.2.2（与 Registry 一致，冲突裁定为 2.2.2）；Python SDK PyPI 稳定版 **0.12.1**，1.0.0rc3（2026-10-12）预发布；ZCode 官方仓 `zai-org/ZCode`（Apache-2.0，v3.15.1）README 无 ACP。详见 `20-同类开源/refs-commits-V0.0.2.md`。下文 0.91.0 等版本号为 V0.0.1 快照值。

> 版本：V0.0.1 研究稿 · 撰写日期：2026-10-16（Asia/Shanghai）
> 范围：协议本体、会话语义、SDK、各 Agent 的 ACP 支持情况、与同名协议的区分、对 WorkFleet 的设计约束。
> 标签约定：`已确认`（读到官方文档/源码原文）· `部分确认`（官方来源有但不完整/存在冲突，或仅社区实测）· `证据不足`（未找到权威来源，不得作为设计前提）

---

## 0. 结论速览（先给答案）

| # | 结论 | 标签 |
|---|---|---|
| C1 | 本产品语境下的 "ACP" = **Agent Client Protocol**（Zed 发起，现由 `agentclientprotocol` 组织维护），用于"客户端（编辑器/网关）↔ 编码 Agent"。**不是** IBM/BeeAI 的 Agent Communication Protocol（已于 2025-08 并入 A2A 并归档），也不是 A2A。 | 已确认 |
| C2 | 传输：JSON-RPC 2.0，**stdio + 换行分隔 JSON（NDJSON）**，客户端拉起 Agent 子进程；Streamable HTTP/WebSocket 仍是 RFD 草案。 | 已确认 |
| C3 | WorkFleet 在输入侧扮演 **ACP Client**：拉起 `claude-agent-acp` / `codex-acp` / `agent acp`（Cursor）/ `openclaw acp` / `gemini --acp` 等子进程，同一连接可承载多个 session。 | 已确认 |
| C4 | 会话恢复有两条路：`session/load`（**回放全部历史**，能力位 `loadSession`）与 `session/resume`（**不回放**，能力位 `sessionCapabilities.resume`）；另有 `session/list`、`session/close`、`session/delete`，`session/fork` 仍为 unstable。 | 已确认 |
| C5 | ACP **没有** "/clear" 原语；"新开对话" 在协议层 = `session/new`（必要时 `session/close` 旧会话）。斜杠命令通过 `available_commands_update` 由 Agent 声明，是否含 `/clear` 取决于 Agent 实现。 | 已确认（协议层）/ 部分确认（各 Agent 斜杠命令清单） |
| C6 | 权限审批是**客户端→用户**的往返：Agent 发 `session/request_permission`，客户端必须回复，否则工具调用阻塞——这正是"把审批推到微信/飞书"的协议锚点。 | 已确认 |
| C7 | ACP v2（`protocolVersion: 2`）已在 schema 中出现但整体标为 **draft**：移除 `session/load`、fs/terminal 客户端方法、session modes；`session/prompt` 响应不再代表 turn 结束。**V0.0.1 必须以 v1 为主、v2 做特性开关。** | 已确认 |
| C8 | 原生/适配支持：Cursor、Gemini CLI、OpenClaw、Qwen Code、Kimi、OpenCode 等原生；Claude Code、Codex 走官方生态适配器；**ZCode 官方 app-server 不是 ACP**（社区有 zcode-acp 适配）；**Coze 不是本地 CLI，不讲 ACP**。 | 已确认 / 部分确认（见 §9） |

---

## 1. 证据来源与快照（可复现）

| 来源 | 位置 / 版本 | 说明 |
|---|---|---|
| ACP 规范仓库 | `git clone --depth 1 https://github.com/agentclientprotocol/agent-client-protocol` → `/workspace/work/refs/agent-client-protocol`，commit `9bec5b0`（2026-10-16） | 原 `zed-industries/agent-client-protocol` 已迁移到 `agentclientprotocol` 组织；CHANGELOG 最新为 v1.11.0（2026-10-09）、schema v2.0.0-alpha.8 |
| 方法清单 | `schema/v1/meta.json`、`schema/v1/meta.unstable.json`、`schema/v2/meta.json` | 方法名的权威来源 |
| 协议文档 | `docs/protocol/v1/*.mdx`（transports / session-setup / prompt-turn / tool-calls / session-list …）、`docs/protocol/v2/migration.mdx` | 同 https://agentclientprotocol.com |
| Claude 适配器 | `/workspace/work/refs/claude-code-acp`，commit `872e93f`（2026-10-15），包名 `@agentclientprotocol/claude-agent-acp@0.91.0`，依赖 `@anthropic-ai/claude-agent-sdk@0.3.300` | GitHub 已重定向到 agentclientprotocol 组织 |
| Codex 适配器 | `/workspace/work/refs/codex-acp`，commit `296069e`（2026-07-22），`Cargo.toml` 版本 0.16.0、依赖 `agent-client-protocol =0.14.0` | ⚠️ 与 ACP Registry 中 `codex-acp 2.2.2`（`@agentclientprotocol/codex-acp`）不一致，本地克隆可能是 zed-industries 旧仓，**以 Registry 版本为准，源码引用仅作结构参考**（部分确认） |
| ACP Registry | `curl https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json` → `/workspace/work/refs/acp-registry.json`（42 个 Agent） | 含每个 Agent 的启动命令与参数 |
| OpenClaw ACP | https://docs.openclaw.ai/cli/acp | 兼容矩阵 |
| Cursor ACP | https://cursor.com/docs/cli/acp | 方法流与扩展方法 |
| IBM ACP 归档 | https://lfaidata.foundation/communityblog/2025/08/29/acp-joins-forces-with-a2a-under-the-linux-foundations-lf-ai-data/ ；https://github.com/i-am-bee/acp | 命名辨析 |

---

## 2. 命名辨析：三个 "ACP" + A2A

| 名称 | 发起方 | 解决什么 | 传输 | 现状 | 是否适用本产品 |
|---|---|---|---|---|---|
| **Agent Client Protocol** | Zed → agentclientprotocol 组织 | 编辑器/客户端 ↔ 编码 Agent（会话、流式输出、工具调用、权限） | JSON-RPC over stdio | 活跃，v1 稳定、v2 草案 | ✅ **输入侧核心协议** |
| Agent Communication Protocol | IBM Research / BeeAI | Agent ↔ Agent（REST，HTTP-native） | HTTP | 2025-08 并入 A2A，仓库归档 | ❌ 不要以此设计 |
| A2A (Agent2Agent) | Google → Linux Foundation | 跨组织 Agent 互调、任务委派 | HTTP/JSON-RPC/SSE | 活跃 | ⚠️ 仅在"总控模式"需对接外部 Agent 时作为可选扩展 |
| Agentic Commerce Protocol | OpenAI/Stripe | Agent 购物支付 | HTTP | 活跃 | ❌ 无关 |

证据：IBM 官方页面 "ACP is now part of A2A under the Linux Foundation"（https://research.ibm.com/projects/agent-communication-protocol）；Zed 讨论区明确两者不同（https://github.com/zed-industries/zed/discussions/37519）。`已确认`

**设计含义**：文档、代码、配置中统一写 `ACP(Agent Client Protocol)`，模块命名 `acp-client`，避免与 A2A 混淆；总控模式若需要"Agent 互开会议"，**不靠 ACP 自身**（ACP 没有 Agent↔Agent 语义），而是由 WorkFleet 网关在多个 ACP 会话之间做编排。

---

## 3. 传输与报文

`docs/protocol/v1/transports.mdx` 原文要点（`已确认`）：
- JSON-RPC 2.0，UTF-8。
- **stdio**：客户端以子进程方式启动 Agent；Agent 从 stdin 读、向 stdout 写；消息以 `\n` 分隔，**不得内嵌换行**；stderr 可写日志；stdout 不得写任何非 ACP 消息。
- **Streamable HTTP**：draft，RFD `docs/rfds/streamable-http-websocket-transport.mdx` 讨论中。
- 允许自定义传输，但须保持 JSON-RPC 格式与生命周期。

**对 WorkFleet 的硬约束**：
1. 每个输入端 Agent = 一个子进程，必须在设备上运行（Agent 要读写本机代码仓）。因此 "两端直连" 中的输入端连接器**必须是本机进程**，云端只能做中转（参见 04 文档的 Edge/Hub 划分）。
2. stdout 纯净性：包装脚本（如 `npx`）的横幅输出会污染流，OpenClaw 文档专门给出 `OPENCLAW_HIDE_BANNER=1` 规避。实现时需对每个 Agent 做"首行非 JSON 即报错并隔离"的防护。
3. 换行分帧 + 大消息：文件内容/diff 可能很大，读取端需要按行缓冲且设上限（建议 16–32 MiB/行，超限关闭会话并告警）。

---

## 4. 方法全集（以 schema/meta.json 为准）

### 4.1 v1 稳定（`schema/v1/meta.json`）

| 方向 | 方法 | 作用 |
|---|---|---|
| Client→Agent | `initialize` | 版本与能力协商 |
| | `authenticate` / `logout` | 认证（方法 ID 由 Agent 在 `authMethods` 声明，如 Cursor 的 `cursor_login`） |
| | `session/new` | 新建会话（`cwd`、`mcpServers`） |
| | `session/load` | 加载并**回放**历史（需 `loadSession: true`） |
| | `session/resume` | 恢复且**不回放**（需 `sessionCapabilities.resume`） |
| | `session/list` | 列出会话（需 `sessionCapabilities.list`，支持游标分页、cwd 过滤） |
| | `session/close` | 关闭活动会话并释放资源（需 `sessionCapabilities.close`） |
| | `session/delete` | 删除会话 |
| | `session/prompt` | 发送一轮用户输入（v1 中响应即 turn 结束，带 `stopReason`） |
| | `session/cancel` | 通知：取消当前 turn |
| | `session/set_mode` / `session/set_config_option` | 切换模式/配置（模型、权限模式等） |
| Agent→Client | `session/update` | 通知：流式内容、工具调用、计划等 |
| | `session/request_permission` | 请求：工具执行审批 |
| | `fs/read_text_file` / `fs/write_text_file` | 请求客户端读写文件（客户端声明能力后） |
| | `terminal/create` / `output` / `release` / `wait_for_exit` / `kill` | 请求客户端代开终端 |
| | `elicitation/create` / `elicitation/complete` | 结构化向用户提问 |
| 双向 | `$/cancel_request` | 取消某个进行中的请求 |

### 4.2 v1 unstable（`meta.unstable.json` 额外项）
`session/fork`、`providers/list|set|disable`（客户端托管 LLM 路由）、`mcp/message`（MCP-over-ACP）、`nes/*`（Next Edit Suggestions）、`document/did*`。`已确认`（存在于 unstable schema，**不承诺稳定**）

### 4.3 v2（`schema/v2/meta.json`，draft）
`initialize`、`auth/login`、`auth/logout`、`session/new|set_config_option|prompt|cancel|list|delete|resume|close`；客户端方法仅剩 `session/request_permission`、`session/update`、`elicitation/*`。迁移文档五要点：①`session/prompt` 响应不再结束 turn，改由 `state_update` 通知；②更新改为按 ID upsert；③去掉 fs/terminal/session modes；④能力重组；⑤枚举可扩展。`已确认`（来源 `docs/protocol/v2/migration.mdx`）

---

## 5. 一次完整交互的生命周期（v1）

```
Client(WorkFleet)                         Agent 子进程
  | spawn + stdio pipes ------------------------> |
  | initialize{protocolVersion:1, clientCapabilities{fs,terminal}} -> |
  | <- {protocolVersion, agentCapabilities{loadSession, sessionCapabilities{list,resume,close,fork?}, promptCapabilities}, authMethods}
  | authenticate{methodId}（如需要） ---------------> |
  | session/new{cwd, mcpServers[]} ---------------> |
  | <- {sessionId, modes?, configOptions?}
  | <- session/update{available_commands_update}   （Agent 声明斜杠命令）
  | session/prompt{sessionId, prompt:[ContentBlock]} -> |
  | <- session/update{agent_thought_chunk | agent_message_chunk | plan | tool_call | tool_call_update | usage_update ...}
  | <- session/request_permission{toolCall, options[]}   （阻塞，等待回复）
  | {outcome:{outcome:"selected", optionId}} ----> |
  | <- session/prompt 响应 {stopReason: end_turn|max_tokens|max_turn_requests|refusal|cancelled}
  | session/cancel（可选，通知） ----------------> |
  | session/close（可选） ------------------------> |
```

`session/update` 变体（v1，`docs/protocol/v1/prompt-turn.mdx` 表格原文）：`user_message_chunk`、`agent_message_chunk`、`agent_thought_chunk`、`tool_call`、`tool_call_update`、`plan`、`available_commands_update`、`current_mode_update`、`config_option_update`、`session_info_update`、`usage_update`、`notice`（需客户端 `session.notices`）、`compaction_update`、`compaction_summary_chunk`（需 `session.compaction`）。`已确认`

`stopReason`：`end_turn`、`max_tokens`、`max_turn_requests`、`refusal`、`cancelled`。`已确认`

权限选项 `kind`：`allow_once`、`allow_always`、`reject_once`、`reject_always`（`docs/protocol/v1/tool-calls.mdx`）；客户端回复的是 Agent 给出的 `optionId`。注意 Cursor 文档里的 `allow-once` 等是**它的 optionId 取值**，与 `kind` 枚举不是一回事——适配层必须按 `kind` 归一化、按 `optionId` 回复。`已确认`

---

## 6. 会话持久化与恢复语义（本产品最关键的部分）

| 操作 | 能力位 | 行为 | 对需求的映射 |
|---|---|---|---|
| `session/new` | 基线 | 新会话，新 `sessionId` | "/clear 新开对话" |
| `session/load` | `agentCapabilities.loadSession` | **必须**通过 `session/update` 回放整个对话，回放完再响应（`session-setup.mdx` L134、L189） | "查看对话记录"可借此拿到历史；网关重启后重连 |
| `session/resume` | `sessionCapabilities.resume` | **不得**回放历史，仅恢复上下文与 MCP 连接（L254） | 网关崩溃重启后快速续接，历史由网关自身存储提供 |
| `session/list` | `sessionCapabilities.list` | 游标分页、可按 `cwd` 过滤；`session_info_update` 推送标题等元数据 | 后台"按 session/resume ID 查询历史" |
| `session/close` | `sessionCapabilities.close` | 取消进行中工作并释放资源 | 清理闲置会话、限制并发 |
| `session/fork` | unstable | 复制会话 | 总控模式"分支试错"（可选） |
| v2 | — | `session/load` 被 `session/resume{replayFrom:{type:"start"}}` 取代，`list`/`close`/`resume` 成为必选 | 适配层抽象为 `resume(sessionId, {replay})` 一个接口 |

适配器实测能力（源码）：
- `claude-agent-acp`：`loadSession: true`，`sessionCapabilities: { fork:{}, list:{}, resume:{} }`（`src/acp-agent.ts` L2889–2928），并实现 `resumeSession`、`unstable_forkSession`。`已确认`
- `codex-acp`（本地克隆版本）：`load_session(true)`、`resume(SessionResumeCapabilities)`、`list_sessions`（从 thread_store 按 UpdatedAt 倒序分页，`src/codex_agent.rs` L455–461、L725+）。`部分确认`（版本差异见 §1）
- `openclaw acp`：`list`/`resume`/`close` 已实现，`loadSession` 部分（仅桥接创建的会话能完整回放，默认 16 MiB 回放预算）。`已确认`
- Cursor `agent acp`：文档写明 `session/new` 与 `session/load`。`已确认`

**关键洞察（苏格拉底追问后保留）**：
- `sessionId` 的**命名空间属于 Agent**。Claude 的 sessionId 与 `~/.claude/projects/<proj>/<id>.jsonl` 对应；Codex 的 thread id 与 `~/.codex/sessions/YYYY/MM/DD/rollout-*-<id>.jsonl` 对应（见 02 文档）。WorkFleet 必须自建 `fleet_session_id ↔ (agent_kind, agent_session_id, cwd, device_id)` 映射表，不能假设跨 Agent 唯一。
- "查看两端对话记录"不应依赖 `session/load` 回放（成本高、并非所有 Agent 支持、OpenClaw 有预算上限），**应由网关在流经时落库**（事件溯源），`session/load` 仅作冷启动补数。

---

## 7. 客户端能力（fs / terminal）取舍

- v1 允许 Agent 请求客户端读写文件、开终端；但 Claude/Codex/Cursor 适配器都在本机自己执行工具，客户端不提供也能工作（Cursor 示例代码 `clientCapabilities: { fs: {readTextFile:false, writeTextFile:false}, terminal:false }`）。`已确认`
- v2 直接删除这些方法。`已确认`
- **决策**：WorkFleet V0.0.1 **不声明 fs/terminal 能力**（声明为 false），理由：①网关通常不在代码编辑器语境；②v2 将移除；③减少攻击面。代价：依赖客户端 fs 的少数 Agent 可能功能降级——需在接入测试中逐个验证（`证据不足`：哪些 Agent 强依赖客户端 fs，未逐一实测）。

---

## 8. SDK

| 语言 | 包 | 来源 | 标签 |
|---|---|---|---|
| TypeScript | `@agentclientprotocol/sdk`（claude-agent-acp 源码直接 import） | `docs/libraries/typescript.mdx`；`claude-code-acp/src/clear-context-coordinator.ts` | 已确认 |
| Rust | crate `agent-client-protocol`（codex-acp 依赖 `=0.14.0`，features `unstable`） | `docs/libraries/rust.mdx`；codex-acp `Cargo.toml` | 已确认 |
| Python | `agent-client-protocol`（github agentclientprotocol/python-sdk，`uv add agent-client-protocol`） | `docs/libraries/python.mdx` | 已确认 |
| Java / Kotlin | agentclientprotocol/java-sdk、kotlin-sdk | `docs/libraries/*.mdx` | 已确认 |
| Go | 社区：coder/acp-go-sdk 等多个 | `docs/libraries/community.mdx` | 已确认（社区，非官方） |

**选型建议**：网关核心若用 TypeScript/Node，直接用官方 TS SDK（与 claude-agent-acp 同源、更新最快）；若追求高并发与单二进制分发，用 Rust crate。Go 只有社区 SDK，风险较高。

---

## 9. 各输入端的 ACP 支持（概要，细节见 02）

| Agent | ACP 方式 | 启动命令（Registry/文档原文） | 标签 |
|---|---|---|---|
| Claude Code | 适配器 `@agentclientprotocol/claude-agent-acp`（基于 Claude Agent SDK） | `npx @agentclientprotocol/claude-agent-acp@0.91.0` | 已确认 |
| Codex CLI | 适配器 `@agentclientprotocol/codex-acp` | `npx @agentclientprotocol/codex-acp@2.2.2` | 已确认（Registry） |
| Cursor | 原生 | `agent acp`（Registry 中为 `cursor-agent acp`） | 已确认 |
| Gemini CLI | 原生 | `npx @google/gemini-cli --acp` | 已确认 |
| OpenClaw | 原生（Gateway 桥） | `openclaw acp [--url wss://… --token-file … --session agent:main:main]` | 已确认 |
| ZCode（智谱 Z.ai） | **官方非 ACP**：`zcode -p` 与 `zcode app-server --stdio`（自定义 JSON-RPC 风格，无 `jsonrpc` 字段、无 initialize） | 社区适配：`zcode-acp`（多个第三方实现，自称 "Unofficial"） | 部分确认（来源：multica issue #5361 实测记录、zai-org/ZCode README） |
| Coze（扣子） | **不适用**：云端智能体平台，通过 OpenAPI `/v3/chat` 调用 | — | 已确认（无 ACP 证据） |
| 其他原生 | Qwen Code（`--acp`）、Kimi（`kimi acp`）、OpenCode（`opencode acp`）、GitHub Copilot CLI、Codebuddy（腾讯，`--acp`）、Goose 等 | Registry | 已确认 |
| GLM 社区代理 | `glm-acp-agent`（个人作者，非智谱官方） | Registry | 已确认（但非官方） |

---

## 10. 5W1H 拆解

**What**：ACP 是一份"客户端驱动、Agent 子进程、JSON-RPC/stdio"的协议，定义会话、流式更新、工具审批与会话持久化。WorkFleet 要做的是"多 Agent × 多 IM"的路由网关，ACP 只覆盖其中 **Agent 一侧**；IM 一侧完全没有标准，需要自定义 OutputAdapter。
**Why**：用户痛点是"一个微信要轮流绑定 5+ 工具"。根因不是协议缺失，而是**每个工具各自实现一个 IM 渠道**（例如 ZCode 自带飞书/微信 Bot、Claude Code 自带 Remote Control）且微信 ClawBot 每账号仅一个 Bot（见 03）。ACP 让网关可以**统一驱动**多个 Agent，从而只占用一个微信绑定——这才是方案成立的根本理由。
**Where/When**：ACP 进程必须运行在拥有代码仓的设备上；`initialize` 必须先于一切；`session/load` 仅在 `loadSession` 为真时可用；v2 仅在双方协商为 2 时启用。
**Who**：协议方 agentclientprotocol 组织；适配器维护方（Zed/JetBrains/Anthropic/OpenAI 联合署名，见 Registry `authors`）；WorkFleet 是 Client 实现者。
**How**：`AcpInputAdapter` 统一封装 spawn→initialize→(authenticate)→new/load/resume→prompt→事件流→permission→cancel/close；能力位驱动功能开关。
**What if**：
- 若某 Agent 不支持 `loadSession`/`resume` → 只能新建会话，历史仅来自网关自存储；在 UI 标灰"恢复"。
- 若 Agent 升级到 v2 而我们只实现 v1 → 协议规定版本协商，Agent 应降级回答 v1，否则断开并告警。
- 若适配器（claude-agent-acp）依赖的 Claude Agent SDK 行为变化 → 锁版本（Registry 给出精确版本）并做冒烟测试。
- 若 stdout 被横幅污染 → 首帧校验失败，隔离该 Agent。
- 若需要远程设备上的 Agent → ACP 无官方网络传输，需要在设备侧跑 Edge 代理（自定义传输，保持 JSON-RPC 帧不变），或采用 OpenClaw 那样 "ACP stdio ↔ WebSocket Gateway" 的桥模式。

## 11. 苏格拉底式追问（每个关键结论至少一轮）

1. **"用 ACP 就能统一所有输入端"凭什么？** 证据：Registry 42 个 Agent、6 个目标中 4 个（Claude/Codex/Cursor/OpenClaw）有 ACP 路径。反证：ZCode 官方协议不是 ACP、Coze 是云 API。→ 结论修正为"**ACP 是主通道，必须保留 CLI/HTTP 两类非 ACP 适配器**"。
2. **证据是否最新？** 规范仓 commit 为今日（2026-10-16）；codex-acp 本地克隆是 7 月版本且与 Registry 版本号不一致 → 已降级为"部分确认"。
3. **是否把"支持 session/load"误当成"能看历史"？** 是的风险存在：OpenClaw 回放有 16 MiB 预算、老会话退化为纯文本。→ 历史查询改为网关自存储为主。
4. **v1 稳定是否足以"进入下一阶段"？** v1 已到 1.11.0，有大量生产客户端（Zed、JetBrains、Neovim）。足以作为 V0.0.1 基线。但 v2 已在推进，`session/load` 将被移除 → 接口层必须抽象。

## 12. 双向钢人论证

**支持"以 ACP 为输入侧主协议"**：①官方 schema 与多语言 SDK；②主流 Agent 已原生或官方适配；③会话 list/resume/close 标准化，直接满足"按 session 查询""新开对话"；④权限请求天然映射为 IM 审批卡片；⑤OpenClaw 已证明 "ACP ↔ 聊天渠道" 的桥接模式可行。
**反对**：①适配器层多了一跳（Claude/Codex 不是原生 ACP，而是 SDK 包装），行为可能滞后于原生 CLI（如新斜杠命令）；②stdio 只能本机，远程/多设备需要自建传输；③v2 破坏性变更（prompt 生命周期重设计）会迫使重写事件处理；④每个 ACP 进程常驻内存，"5+ Agent × 多项目"并发时资源压力大（`证据不足`：未实测单进程内存）；⑤ACP 不定义 Agent↔Agent，总控"开会"要网关自己编排。
**裁决**：反对意见①③④成立但可缓解（锁版本、接口抽象、会话池+空闲回收）；②⑤是架构必须承担的工作，已纳入 04 设计。结论保持：**ACP 为主，CLI/HTTP 为辅**。

## 13. 最终判断

- **明确结论**：输入侧采用 ACP v1 作为一等协议；对 ZCode（官方 app-server）与 Coze（OpenAPI）提供专用适配器；协议抽象层预留 v2。
- **依据**：§3–§9 引用的 schema/文档/源码。
- **成立前提**：Agent 在本机运行；用户已在各 Agent 完成登录（ACP `authenticate` 多为"已预先登录"）。
- **局限**：未在本机实际拉起各 Agent 做端到端实测；资源占用、并发上限均为`证据不足`。
- **风险**：适配器版本漂移、v2 迁移、ZCode 私有协议变动、厂商条款（社区 zcode-acp 自述可能违反 ToS）。
- **下一步**：①在一台开发机上用 TS SDK 写最小 Client，依次对 claude-agent-acp / codex-acp / cursor agent acp / openclaw acp 跑 `initialize→new→prompt→permission→list→resume→close` 冒烟并记录能力位；②测量单 Agent 常驻内存与冷启动时间。
- **是否允许进入下一阶段（接口设计）**：**允许**，以 04 文档的抽象为准，实测数据回填后再定并发参数。
