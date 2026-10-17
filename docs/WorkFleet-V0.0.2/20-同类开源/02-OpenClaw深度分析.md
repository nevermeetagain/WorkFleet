# 02 · OpenClaw 深度分析（含 `@openclaw/acpx` 插件）

> 【V0.0.2更新】2026-10-17：HEAD `acd2763`（+894 提交，最新正式版 v2026.10.4）。compare API 仅返回最后 250 条，以 cron/runtime 性能、ACP 读取测试为主；**钉钉是否新增、订阅广播是否新增未全量核查（证据不足）**；本报告结论维持 `3dc6e49` 口径。

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/openclaw/openclaw |
| 分析版本 | `3dc6e49c07fb138c0029a411c1745974f23d144c`（2026-10-16 14:00 CST） |
| 获取方式 | `git clone` 反复报 HTTP 502，改用 codeload 源码包（`tar.gz/<sha>`，177 MB，gzip 校验通过）。解压到 `/workspace/work/refs/openclaw`，SHA 记录在 `.COMMIT_SHA` |
| Stars / 语言 / 许可证 | 392,133 / TypeScript / MIT（`package.json:18`） |
| 规模 | `extensions/` 下约 200 个插件（provider、channel、memory、tools）；`src/` 下 120 个子目录 |

---

## 1. 5W1H

- **What**：自托管的"个人 AI 网关"。Gateway 进程统一管理 channels（IM）、agents（带独立 workspace、会话、凭证的人格）、bindings（路由）、cron（自动化）、memory、skills。Coding CLI 不是一等输入，而是以 **ACP harness**（acpx 插件）或 **CLI backend** 的形式被 OpenClaw Agent 调用。
- **Why**：作者的定位是"把助手带到你所在的聊天软件"，而 AideanFleet 的定位是"把多个工具汇聚到少量 IM"。两者方向相反，但路由层可以互通。
- **Where/When**：Gateway 默认端口 `18789`（`docs/web/control-ui.md:13`），配置文件 `~/.openclaw/openclaw.json`（JSON5，`docs/gateway/configuration.md:10`）。
- **Who**：内置 channel 有 telegram、discord、feishu、slack、whatsapp、signal、matrix、msteams 等（见 `extensions/` 列表）；**微信**由腾讯维护的外部插件提供（`docs/channels/wechat.md`）；**QQ** 由 `@tencent-connect/openclaw-qqbot` 提供（`docs/channels/qqbot.md`）；`docs/channels/` 中**没有钉钉**。
- **How**：入站 → channel 插件规范化 → `resolveAgentRoute` 选出 agent 和 sessionKey → agent turn（内置模型、ACP harness 或 sub-agent）→ 原路回复。
- **What if**：如果把 OpenClaw 只当"路由 + 渠道层"用、把 Coding CLI 当 ACP harness 用，AideanFleet 的多对多可以用 agents × bindings × accounts 表达；代价是必须接受 OpenClaw 自己的 Agent 运行时（模型、凭证、记忆）。

## 2. 架构与代码证据

| 模块 | 证据 | 说明 |
|---|---|---|
| 路由解析 | `src/routing/resolve-route.ts:269` `resolveAgentRoute`；`:405-424` 优先级为 peer → parentPeer → peer 通配 → guild+roles → guild → team → account → channel → default | 层次化绑定匹配，并带路由缓存（`:283-300`） |
| 路由结果 | `src/routing/resolve-route.ts:59-84` `{agentId, channel, accountId, dmScope, groupScope, sessionKey, matchedBy}` | 可以调试 |
| 会话键 | `docs/channels/channel-routing.md`："agent:<agentId>:main"、"agent:<id>:<channel>:group:<id>"、`:thread:` / `:topic:` 后缀；`session.dmScope` 有 main / per-peer / per-channel-peer / per-account-channel-peer 几种 | 会话隔离粒度可配 |
| 多 Agent | `docs/concepts/multi-agent.md`：每个 agent 有独立的 workspace、agentDir、`openclaw-agent.sqlite` 会话库；多个 channel 账号 | 对应"团队模式"的核心 |
| 多账号 | `docs/channels/channel-routing.md`：`AccountId`、`channels.<ch>.defaultAccount` | 同一种 IM 可以挂多个 bot |
| Broadcast groups | `docs/channels/broadcast-groups.md`：`broadcast["telegram:-100123"]={agents:[…], maxRounds≤4, maxTurns≤32, mentionGating}`，状态为 experimental | **多个 Agent 回复同一入站**（会议雏形），不是 1→N 推送 |
| Cron | `src/cron/schedule.ts:213-` `computeNextRunAtMs` 支持 `at` / `every` / `cron(+tz)`；`src/cron/types.ts:55-68` `CronDelivery{mode, channel, to, accountId, threadId, completionDestination(webhook), failureDestination}` | 投递目标是**单个**；另外还有 heartbeat、stagger、run-history 等 |
| ACP 运行时 | `extensions/acpx/README.md`；`extensions/acpx/src/runtime.ts`、`process-reaper.ts`、`session-owner.ts` | ACP harness 的进程租约、回收、会话归属都有实现 |
| ACP 绑定 | `docs/tools/acp-agents/bindings.md`：`/acp spawn codex --bind here`（把当前会话绑定到 ACP 会话）；`/new`、`/reset` 原地重置；`--thread auto` 开子线程 | 支持 IM 端新开会话 |
| ACP 控制面 | `src/acp/`（client.ts、permission-relay.ts、event-ledger.ts、persistent-bindings.*） | 权限中继和事件账本 |
| OpenClaw 作为 ACP Server | `docs/tools/acp-agents.md`："`openclaw acp` Bridge mode" | 可以被 cc-connect 或 acpx 当输入端调用 |
| 记忆 | `extensions/memory-core`、`memory-lancedb`、`memory-wiki`、`active-memory`；`docs/concepts/memory-*.md` | 有向量记忆和 wiki 记忆 |
| UI | `ui/src`；`docs/web/control-ui.md`；另有 macOS / iOS / Android 原生 App（`apps/`） | Control UI 中有 Config 标签页 |
| 存储 | 每个 agent 一个 SQLite（`node:sqlite`，见 `src/state/*`，如 `agent-database-admission.ts`） | |

## 3. 需求匹配

| 需求 | 匹配 | 得分 | 说明 |
|---|---|---|---|
| IN（15） | ● | 12 | 通过 acpx 接 Claude Code、Codex、Cursor、Gemini、Copilot、OpenCode 等（`docs/tools/acp-agents.md`）；OpenClaw 自身也算一个输入；Zcode `证据不足`；Coze 需自建 provider 或工具 |
| OUT（15） | ◐ | 12 | 飞书、Telegram、Discord 内置；微信、QQ 通过腾讯插件；**钉钉缺失**；微信插件只支持单聊（`docs/channels/wechat.md`："declares direct chats only"） |
| M1（10） | ◐ | 6 | 多个 agent 可以共用一个 channel 账号，按 peer 或群路由；但同一个 DM 对端只能对应一个 agent，要切换得靠 `/acp spawn --bind` 或改 binding |
| M2（10） | ◐ | 4 | 没有订阅和扇出；cron 投递单目标；agent 的 message 工具可以主动发消息（需要编排） |
| M3（10） | ● | 8 | agents × accounts × bindings 天然支持多对多，场景示例（微信 / QQ / 飞书分线）可直接配置 |
| UI（10） | ● | 8 | Control UI + Config 标签页 + CLI 向导 |
| CR（5） | ● | 4 | at、every、cron+时区，没有节假日 |
| NS（5） | ● | 5 | `/new` `/reset` |
| HI（5） | ● | 4 | `sessions_history`、session search、ACP resume（`docs/tools/acp-agents/delivery.md`） |
| KB（5） | ◐ | 4 | memory-core、lancedb、wiki 记忆；没有"目录结构图谱" |
| M4（5） | ◐ | 3 | sub-agents、`sessions_spawn`、broadcast groups 的多轮讨论可以拼出"会议"；没有显式经理人把关链路 |
| LP（5） | ◐ | 2 | active-memory、记忆写入；画像自更新 loop `证据不足` |
| **合计** | | **≈72 → 计 68%**（对体量和运维复杂度打折） | |

### 3.1 场景

| 场景 | 结论 |
|---|---|
| 1 6 工具 → 微信 | ◐ 微信单号可以挂多个 ACP 会话，但单个 DM 同一时刻只能绑定一个，切换要靠命令；多工具并行回推到同一 DM 需要自建汇聚 |
| 2 飞书分发两部门 | ● 3 个 agent 各自 bind 到两个飞书群（peer 绑定） |
| 3 总控 | ◐ 可用一个"经理 agent"加 `sessions_spawn(runtime:"acp")` 驱动子 harness，需要写 skill 或 prompt，没有现成的审核闸门 |
| 4 9 点群发 | ○ 没有订阅者模型；cron 一个任务一个目标 |

## 4. 全维度

| 维度 | 评估 |
|---|---|
| 前端 | Control UI（Web）+ 原生客户端，成熟度高 |
| 后端 | Node 22+ / TS 单 Gateway 进程，插件化程度极高；学习曲线陡 |
| 数据 | 每个 agent 一个 SQLite（会话、凭证、路由状态）+ 插件自有存储；cron store；ACP event-ledger |
| 交互 | 斜杠命令（/acp、/codex、/new、/session）、提及门控、配对（pairing） |
| 逻辑 | 确定性路由（"模型不选渠道"，见 `channel-routing.md`）；会话锁、准入（`src/sessions/*admission*`） |
| 组件 | channel / provider / memory / tool 插件契约（`src/plugin-sdk`） |
| 复用 | 路由算法和会话键设计**最值得借鉴**；整体 fork 成本极高 |
| 拓展 | npm 插件生态（`openclaw plugins install`）、ClawHub |
| 性能 | 路由缓存、worker 化账本；单进程 Node，大规模扇出需要外部队列 |
| 配置 | JSON5 + Web Config + doctor 校验 |
| 知识库 | memory 系列插件 |
| 响应 | 流式、线程回复；不同渠道能力有差异 |
| 存储 | SQLite（每个 agent 一份），适合个人规模 |
| 资源 | 体量大（源码包 177 MB），常驻内存高于 Go 单二进制（未实测，`证据不足`） |
| 安全 | allowFrom、配对、沙箱、工具策略、secret 契约（`extensions/*/secret-contract-api.ts`）、SECURITY.md |
| 许可证 | MIT（核心）；**腾讯微信插件 NOASSERTION**，商用前需确认 |

## 5. 双向钢人

**判断："OpenClaw 比 cc-connect 更适合当底座"**
- 支持：多对多路由是一等公民（bindings 分层与 accounts），会话隔离粒度丰富，记忆、cron、UI、ACP 都齐全，生态极大。
- 反对：(1) 它是"Agent 网关"，Coding CLI 只是 harness，所有消息都要先过 OpenClaw Agent 的模型或运行时，增加延迟和成本（ACP 直连模式 `--bind here` 能缓解）；(2) 钉钉缺失，微信只支持单聊；(3) 代码体量和变更频率极高（当天还有提交），fork 难以跟进；(4) 场景 4 不满足。
- 判断：**作为"参考设计 + 可选插件宿主"优于 cc-connect；作为轻量底座劣于 cc-connect**。如果用户接受 Node 生态并希望复用记忆、技能，可以选 OpenClaw，自写钉钉 channel 插件和广播插件。

## 6. 缺口与补齐

| 缺口 | 补齐 |
|---|---|
| 钉钉 | 移植 cc-connect `platform/dingtalk` 或 AstrBot `sources/dingtalk` 的逻辑，写成 OpenClaw channel 插件 |
| 1→N 广播 / 订阅 | 自建插件：Subscription 表 + cron 触发 + 按渠道限流；参考 Apprise |
| 总控审核闸门 | 经理 agent + skill；借鉴 AionCore Team 的 Mailbox / TaskBoard |
| 节假日 cron | 同 01 |
| 多工具汇聚到同一 DM | 自建"汇聚 agent"：订阅多个 ACP 会话的完成事件（`docs/tools/acp-agents/delivery.md`），合并后投递 |

## 7. 最终判断

- 加权约 **68%**，在入围项目中最高，但**未达"大部分"**。
- 前提：接受 Node / OpenClaw Agent 运行时；钉钉自补。
- 局限：未实际运行；资源占用未实测；微信插件许可证不明。
- 下一步：用 PoC 验证"单微信账号 + 2 个 ACP harness + bindings 切换"的体验，以及 `openclaw acp` 作为 cc-connect 输入端的可行性。
- 是否进入下一阶段：允许进入底座对比 PoC（与 cc-connect 二选一，或组合使用）。
