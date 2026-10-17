# 01 · cc-connect 深度分析

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/chenhg5/cc-connect |
| 分析版本 | `7da94a4076d4ef9184dfd997336520b9aa0ee837`（2026-10-16 13:40 CST，main HEAD） |
| 本地路径 | `/workspace/work/refs/cc-connect` |
| Stars / 语言 | 15,965 / Go（Web 后台为 React + TS，位于 `web/src`） |
| 许可证 | README 徽章与 `npm/package.json:23` 写 MIT，但**仓库根目录没有 LICENSE 文件**，GitHub API 的 license 字段为 null → `部分确认` |
| 规模 | `core/engine.go` 17,672 行；`core/*.go` 合计约 8.2 万行（含测试） |

---

## 1. 5W1H 第一轮拆解

- **What**：本地常驻进程，把本机的 Coding Agent CLI（以子进程方式运行）桥接到 IM。核心抽象有三个：`Platform`、`Agent`/`AgentSession`、`Engine`（每个 project 一个 Engine）。
- **Why（作者动机）**：让开发者"在手机 IM 上远程操控本地 Claude Code"。这与 WorkFleet 的"多工具 ↔ 一个微信"在输入、输出两端是同一个方向，但它**以 project 为中心，而不是以路由为中心**。
- **Where/When**：运行在开发者自己的设备上（`run_as_user` 只支持 POSIX，见 `config/config.go:512-521`）。各端口：Management API/Web `9820`、Bridge WS `9810`、Webhook `9111`（`config.example.toml:392-470`），**与 Aidean 规定的 3000/3333 无冲突**，但都需要改成可配置的统一入口。
- **Who**：输入端 16 种 agent 适配器（`agent/`），输出端 20 种平台（`platform/`）。
- **How**：TOML 配置 → `main.go` 遍历 `cfg.Projects`，为每个 project 创建 1 个 Agent 和 N 个 Platform，再组装成 Engine（`cmd/cc-connect/main.go:361-421`）。
- **What if**：如果多个 project 配置了同一个 IM 凭证（例如同一个微信 iLink token），会创建多个 Platform 实例各自长轮询。行为未知，`证据不足`。这是 WorkFleet 的关键风险点。

## 2. 架构与关键代码证据

```
IM 平台(Platform) ──MessageHandler──▶ Engine(project) ──AgentSession.Send──▶ Agent 子进程(CLI/ACP)
        ▲                                │  SessionManager(JSON)                 │ Events() chan
        └──────── Reply/Send ────────────┴──── CronScheduler / Timer / Relay ◀───┘
                    Management API(9820) · Bridge WS(9810) · Webhook(9111) · Hooks
```

| 模块 | 证据（文件:行） | 说明 |
|---|---|---|
| 平台抽象 | `core/interfaces.go:39-45` | `Platform{Name, Start, Reply, Send, Stop}`，另有约 30 个可选能力接口（卡片、按钮、打字状态、图片、文件、编辑消息……，`:53-360`） |
| Agent 抽象 | `core/interfaces.go:363-392` | `Agent.StartSession(ctx, sessionID)` 用于创建或**恢复**会话；`AgentSession.Send/RespondPermission/Events/CurrentSessionID/Close` |
| 历史 | `core/interfaces.go:408-411` | `HistoryProvider.GetSessionHistory(sessionID, limit)`，从 Agent 后端的会话文件读取 |
| 注册表 | `core/registry.go:6-52` | `RegisterPlatform/RegisterAgent` 工厂，配合 build tag 做插件化裁剪（如 `plugin_platform_weixin.go` 的 `//go:build !no_weixin`） |
| 装配 | `cmd/cc-connect/main.go:361-421` | 每个 project 对应 1 个 Agent + N 个 Platform → `core.NewEngine` |
| 配置根 | `config/config.go:86-126`、`:491-521` | `Projects[]{Agent, Platforms[], Heartbeat, AutoCompress, ResetOnIdleMins, RunAsUser, Mode=multi-workspace}` |
| 通用 ACP | `agent/acp/session.go:97`（spawn）、`:179` initialize、`:214` session/load、`:234` session/new、`:486` request_permission、`:618` session/prompt、`:718` session/cancel；`agent/acp/list_sessions.go:157` session/list | 完整的 ACP 客户端，可接任意 ACP Agent（包括 `openclaw acp`、`cursor-agent acp`） |
| 微信 ClawBot | `platform/weixin/client.go:20` `defaultBaseURL = "https://ilinkai.weixin.qq.com"`；`core/management.go:242-244` 扫码 setup begin/poll/save | 直接接腾讯 iLink |
| QQ | `docs/qqbot.md`（官方 API v2）、`docs/qq.md`（OneBot v11 + NapCat） | 两种方式都有 |
| 钉钉 | `docs/dingtalk.md:11` Stream 长连接 | 不需要公网 IP |
| 会话 | `core/session.go:388-` `SessionManager`；`:430` GetOrCreateActive；`:444` NewSession；`:487` SwitchSession；`:507` SwitchToAgentSession；`:834` `AtomicWriteFile` 持久化为 JSON | 一个 userKey 可以有多个会话，记录 agentSessionID（即 resume ID） |
| 命令 | `core/engine.go:6797-6840` 内置命令表（new/list/switch/history/search/cron/timer/bind/workspace…）；`:7000` new → `cmdNew` `:7373`；`:9656` cmdHistory；`:8902` cmdSearch | **没有 `/clear`**，可通过 `[[aliases]]` 映射为 `/new`（`config.example.toml:700-720`） |
| 定时 | `core/cron.go:23-41` CronJob{SessionKey, CronExpr, Prompt / Exec, SessionMode reuse/new_per_run, Mute, TimeoutMins}；`:438-` CronScheduler；`go.mod:20` robfig/cron v3；`core/timer.go:17` TimerJob（一次性） | 标准 5 段 cron，加上一次性 timer |
| 中继 | `core/relay.go:24-38` RelayBinding{Platform, ChatID, Bots: project→bot}；`:205` Send；`core/engine.go:16570` `/bind` | 群聊中 bot 与 bot 之间的转发（跨 project） |
| 管理 API | `core/management.go:221-255`（status/config/projects/cron/providers/skills/bridge/setup）；`:1121-1317` sessions 列表、切换、删除；`docs/management-api.zh-CN.md:610` `POST /api/v1/projects/{name}/send` | REST，配 Token 和 CORS |
| Web 后台 | `web/src/pages/{Dashboard,Projects,Sessions,Cron,Providers,Skills,Bridge,System,Chat}` | 嵌入二进制（`embed.go`），标注为 Beta |
| Bridge | `docs/bridge-protocol.zh-CN.md` | 任何语言写的外部**平台**适配器都可以通过 WebSocket 接入 |
| Webhook / Hooks | `config.example.toml:392-498` | 外部系统触发 prompt 或 shell；事件钩子包括 message.received/sent、session.*、cron.triggered、permission.requested |
| 并发 / 队列 | `core/engine.go:32` `defaultMaxQueuedMessages = 5`；`config/config.go:147-149` QueueConfig；`core/session.go:71-152` TryLock / BreakStaleLock | 每个会话串行执行，排队上限 5 条 |
| 限流 | `config.example.toml:289-313` rate_limit / outgoing_rate_limit（可按平台设置） | 有 |
| 存储 | `config/config.go:87` data_dir 默认 `~/.cc-connect`；会话、cron、relay 都存 JSON 文件（`relay_bindings.json` 见 `core/relay.go:49`）；`go.mod:27` 引入 modernc sqlite（用途未细查） | 以文件为主 |
| 性能测试 | `tests/performance/bench_test.go` | 有基准测试 |

## 3. 需求匹配（逐条）

| 需求 | 匹配 | 得分 | 证据 / 说明 |
|---|---|---|---|
| IN 多输入（15） | ● | 13 | Claude Code、Codex、Cursor、Gemini、OpenCode 等原生适配器，加上通用 ACP（OpenClaw 走 `openclaw acp`）。Zcode `证据不足`；Coze 没有现成适配器（需按 Agent 接口包装 HTTP API） |
| OUT 多输出（15） | ● | 15 | 6 个全覆盖：飞书、微信 iLink、QQBot/OneBot、钉钉、Discord、Telegram |
| M1 管理 多对1（10） | ◐ | 5 | 做法有两种：(a) N 个 project 配同一个 IM 凭证（并发冲突 `证据不足`）；(b) 1 个 project 用 `multi-workspace` 模式（只能用同一种 Agent）。都没有"一个 IM 入口通过 `@tool` 前缀切换不同 Agent"的路由 |
| M2 通知 1对多（10） | ◐ | 4 | 一个 project 可挂多个 Platform，但回复回到来源会话；cron 只有单个 SessionKey；`POST /projects/{name}/send` 和 `cc-connect send` 可以推送到指定 session。没有订阅者列表和批量扇出 |
| M3 团队 多对多（10） | ◐ | 6 | 静态的"project × platforms"已经能表达场景示例（产品线 A → 微信，B → QQ，公司 → 飞书），但没有动态路由表和规则 |
| UI 后台配置（10） | ● | 8 | Web 后台 Beta，加 Management API |
| CR 定时（5） | ● | 4 | cron + timer（一次性）+ 自然语言创建；**没有中国法定节假日和调休日历** |
| NS /clear（5） | ● | 5 | `/new` + alias |
| HI 记录（5） | ● | 4.5 | `/list`、`/switch`、`/history`、`/search`，Management API 的 sessions 接口，HistoryProvider 按 agentSessionID 查询 |
| KB 知识库（5） | ○ | 1 | 只有 `/memory`（读写 Agent 指令文件，如 CLAUDE.md），没有向量知识库和目录图谱 |
| M4 总控（5） | ○ | 1 | 只有 relay（bot 间转发），没有经理人 Agent |
| LP 分身 loop（5） | ○ | 0.5 | 只有 heartbeat 和 auto_compress，没有画像自更新 |
| **合计** | | **≈67 → 计 65%**（对 M1 并发风险打折） | |

### 3.1 四个场景

| 场景 | 结论 | 说明 |
|---|---|---|
| 1 三项目 6 工具 → 微信 ClawBot | ◐ `待确认` | 需要 6 个 project 共享 1 个微信 bot（冲突风险 `证据不足`），或者 6 个 ClawBot 账号（正是用户想避免的） |
| 2 飞书 3 分析工具 → 数据部 + 老板 | ◐ | 3 个 project 都挂飞书，各自在两个群里回复，可以做到；但"汇总后再分别推送"没有编排 |
| 3 主项目 + 子项目，总控 | ○ | 没有总控 |
| 4 大量用户每天 9 点推送 | ○ | 没有订阅和扇出；cron 一个任务只对应一个 SessionKey |

## 4. 全维度评估

| 维度 | 评估 |
|---|---|
| 需求 | 输入、输出两端最贴近需求，路由、广播、总控是短板（见 §3） |
| 前端 | React + TS 管理后台嵌入二进制（`web/src/pages/*`）；Beta，可二次开发出"路由矩阵"页面 |
| 后端 | Go 单进程 + goroutine；Engine 巨型文件（1.7 万行），二次开发前需要先拆分 |
| 数据 | Session（含 agentSessionID 和最近 history）、CronJob、TimerJob、RelayBinding、UserMeta；**没有统一的消息事件表** |
| 交互 | 斜杠命令 + 卡片 / 按钮（飞书、Telegram、Discord）；权限审批可在 IM 内完成（`RespondPermission`） |
| 逻辑 | 同一会话串行加锁，排队上限 5；空闲超时、忙锁超时、单轮最大时长（`config/config.go:114-116`） |
| 组件 | Platform / Agent 工厂注册表，配合 build tag 裁剪 |
| 复用 | 可以直接复用：20 个平台适配器、ACP 客户端、cron/timer、Management API。建议作为 Go module 引入或 fork |
| 拓展 | 三条外部扩展路径：Bridge WS（外部平台）、Webhook（外部触发）、Hooks（事件外发） |
| 性能 | Go 原生并发，单二进制；有 bench 测试；每个会话一个 CLI 子进程，资源由 Agent 进程主导 |
| 配置 | TOML，分全局 / project / platform 三级；Web 端可 reload |
| 知识库 | 无（只有 `/memory`） |
| 响应 | stream_preview 流式预览 + instant_reply 即时回执（`config.example.toml:259-289`） |
| 存储 | `~/.cc-connect` 下的 JSON 文件 + AtomicWriteFile；不适合大规模订阅者数据 |
| 资源 | 每个活跃会话占 1 个 Agent 进程；`agent_session_idle_timeout_mins` 可回收空闲进程 |
| 安全 | allow_from / allow_chat 白名单、用户角色（`core/user_roles.go`）、run_as_user 做 OS 级隔离、redact 脱敏（`core/redact.go`）、banned_words、API token |
| 许可证 | `部分确认` MIT（缺 LICENSE 文件，fork 前应通过 issue 请作者补齐） |

## 5. 苏格拉底追问与双向钢人

**结论 A："cc-connect 是最合适的 IM 桥底座"**
- 支持：6 个目标 IM 全覆盖且已核实；通用 ACP；Go 单二进制适合"必须跑在设备上"；社区活跃（当天有合并，HEAD 为 PR #2009）。
- 反对：(1) project 中心模型与"路由中心"不符，要改造 Engine 装配方式；(2) engine.go 过大，fork 后的维护成本高；(3) 许可证文件缺失；(4) 微信同号多实例冲突未验证。
- 已排除：输出端覆盖不足（已核实 6/6）。
- 仍然成立：(1)(2)(3)(4)。其中 (4) 需要实测：用同一 iLink token 起两个进程，观察 getupdates 的行为。
- 判断：**作为"适配器库 + ACP 客户端"来复用是可靠的；直接拿整体当产品形态不够**。

**结论 B："/clear 已满足"**
- 依据：`/new` 位于 `core/engine.go:7000-7001`，aliases 机制见 `config.example.toml:709-711`。
- 反对：alias 只匹配首词；`/new` 只是新建 cc-connect 会话、关闭旧 Agent 进程（`cmdNew` `:7373-7382`），并不等同于向 Claude Code 发送 `/clear`。对用户而言效果相同（新上下文）。
- 判断：`已确认` 功能等价。

## 6. 缺口与补齐方案

| 缺口 | 补齐来源 | 方案 |
|---|---|---|
| 路由层（M1/M3 动态路由，单 IM 入口 `@claude` / `#proj` 切换） | OpenClaw `src/routing/resolve-route.ts:405-424` 的分层匹配思想 | 自建 `RouteTable{match: platform/account/peer/prefix → target: agentInstance}`，Engine 改为多 Agent |
| 1→N 广播 / 订阅（M2、场景 4） | Apprise（扇出）思想；AstrBot `star/context.py:650` 主动消息 | 自建 `Subscription(topic, platform, peer)` + 投递队列 + 每平台限流（复用 outgoing_rate_limit） |
| 单 IM 账号多实例 | — | 自建"平台连接单例池"：同一凭证只建一个 Platform，再按路由分发给多个 Engine |
| 总控 | AionCore `crates/aionui-team`（Leader / Mailbox / TaskBoard）、LangGraph | 新增"Manager Agent"类型：以 ACP 客户端身份驱动多个 Agent，带审核闸门 |
| 知识库 | AstrBot `knowledge_base`（FAISS + BM25 + RRF）、hindsight（他组负责） | 独立 KB 服务，用 MCP 暴露给各 Agent |
| 节假日 cron | — | 自建中国节假日 / 调休日历（数据源待选），在 cron 外层加 `calendar: workday|holiday` 过滤 |
| Coze 输入 | AstrBot `coze_agent_runner.py:28` | 实现 `core.Agent` 接口包装 Coze API |
| 统一消息存储 | — | 追加 SQLite / PG 的 `messages` 表（direction、route、session、agentSessionID），以支持跨端查询 |

## 7. 最终判断

- **结论**：cc-connect 是本赛道"Coding CLI ↔ 中国 IM"覆盖最全的开源实现，加权匹配约 65%。**适合作为输入、输出适配层的复用源或 fork 底座，不能直接满足**多对多路由、广播、总控、知识库。
- **前提**：许可证确为 MIT；同一 IM 凭证单例化改造可行。
- **局限**：未实际运行；微信 iLink 并发行为与 Zcode 支持均为 `证据不足`。
- **下一步**：(1) 本地 build 并以 2 个 project 共用同一个 weixin token 做实测；(2) 提 issue 请作者补 LICENSE；(3) 设计路由层，可选"包一层"或"改 Engine"两种做法。
- **是否进入下一阶段**：允许进入"底座选型对比与 PoC"，`待确认`项需在 PoC 中验证。
