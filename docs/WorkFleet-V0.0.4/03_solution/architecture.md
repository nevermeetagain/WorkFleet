---
id: WF-ARCH
type: architecture
title: WorkFleet 总体架构（v1）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
owner: 规划 Agent（opus 档）
sources: [DEC-001…057, REQ-INBOX-20261017-001/002/003, ADR-001…ADR-012]
---

# WorkFleet 总体架构（v1）

> 证据标签：已确认 / 部分确认 / 证据不足 / 推断。本文只描述“将要实现的结构”；当前仓库无任何业务代码（快照见 `08_knowledge/fact-baseline.md`）。

## 1. 一句话
WorkFleet = **本机节点**（在每个用户电脑上拉起并驱动 ACP 智能体）+ **云中转**（持有 IM 连接、账号、路由、审计、Web 控制台）+ **契约包**（两端唯一共享的语言）。代码、工具凭据、模型 Key 永不离开本机节点（DEC-037/044）；IM 明文经过中转（DEC-047/048：公司用自建中转）。

## 2. 系统上下文

```text
 手机/电脑上的人                         云中转（Ubuntu，香港，443）                    用户电脑（Win/Mac/Linux）
┌──────────────┐  IM 平台长连接/长轮询  ┌──────────────────────────────┐  出站 WSS（节点主动连）  ┌──────────────────────────┐
│ 微信 ClawBot │◀────────────────────▶│ channels 适配器（6 个 IM）    │                         │ relay-link（可连多中转） │
│ 飞书 / Lark  │                      │ routing 路由内核（绑定表）     │◀──────────────────────▶│ agents（ACP Host）        │
│ QQ / 钉钉    │                      │ conversations 会话与消息账本   │   envelope + seq/ack   │  ├ 通用 ACP 适配器       │
│ Telegram     │                      │ approvals / barrier 汇总屏障  │                         │  ├ Coze / Webhook 输入   │
│ Discord      │                      │ identity / tenancy / RBAC      │                         │  └ 每会话一个子进程      │
└──────────────┘                      │ audit / notifications / PWA推送│                         │ supervisor 总控（本机）  │
┌──────────────┐  HTTPS + WSS         │ node-gateway（节点通道）       │                         │ models 模型配置 + 钥匙串 │
│ 浏览器 / PWA │◀────────────────────▶│ web 静态资源（apps/web）       │                         │ twin 分身数据            │
│ = 默认渠道   │                      │ SQLite(WAL) relay.db           │                         │ SQLite(WAL) node.db      │
└──────────────┘                      └──────────────────────────────┘                         │ 本机控制台 127.0.0.1:5100│
                                                                                                 └──────────────────────────┘
```

## 3. 部署单元
| 单元 | 运行位置 | 进程模型 | 对外端口 | 数据 | 依据 |
|---|---|---|---|---|---|
| `apps/relay` | Ubuntu 22.04+/24.04，Node 22 LTS | 单进程（Fastify + ws），systemd；单实例锁 | 443（经 Caddy/Nginx TLS 反代到 127.0.0.1:5101） | `relay.db`（SQLite WAL）+ 附件目录 | DEC-037/039/040/041/051、ADR-003 |
| `apps/node` | Windows 10+/macOS 13+/主流 Linux，Node 22 LTS | 单进程控制面 + 每个智能体会话一个子进程（执行面）；单实例锁；开机自启 | 只绑 127.0.0.1：5100 本机控制台/API，5102 Webhook 输入，5103 MCP，5104 metrics | `node.db`（SQLite WAL）、会话转录、钥匙串 | DEC-002/003/016/021/041/051 |
| `apps/web` | 同一份 SPA 两种构建目标：`relay`（多用户控制台 + 对话 + PWA）与 `node`（本机：工具、模型配置、Key、诊断） | 浏览器 | — | IndexedDB 只做离线草稿缓存 | DEC-010/056/057、ADR-008 |
| `packages/contracts` | 构建期 | — | — | JSON Schema 唯一源 → 生成 TS 类型、ajv 校验器、契约测试 | DEC-028、ADR-002 |
| `packages/testkit` | 测试期 | — | — | FakeAgent（ACP 录制回放）、FakeChannel、FakeRelay | DEC-029 |

端口段 5100–5200（用户指定）：5100 本机控制台、5101 中转内部监听（仅反代可达）、5102 Webhook、5103 MCP、5104 metrics、5110–5119 E2E 测试中转实例、5190–5200 测试预留。中转公网只开 443（DEC-051）。

## 4. 模块划分（按业务边界，PROJECT-STRUCTURE-SPEC §4）

### 4.1 云中转 `apps/relay/src/modules/`
| 模块 | 职责 | 对外公开 API（index.ts） | 不得做 |
|---|---|---|---|
| `identity` | 用户注册/登录、密码（argon2id）、会话 Cookie、TOTP（可选）、API Token | `authenticate()`、`currentPrincipal()` | 存模型 Key |
| `tenancy` | 组织（tenant）、成员、角色（admin/operator/viewer）、邀请 | `assertPermission(principal, action, resource)` | 业务路由 |
| `devices` | 本机节点注册（配对码→设备令牌）、在线状态、主设备、令牌轮换/吊销 | `resolveDevice()`、`isOnline()` | 执行智能体 |
| `projects` | 项目一级对象、主/子项目树、项目成员可见性 | `getProjectTree()` | — |
| `agents-registry` | 智能体实例元数据（别名、设备、项目、适配器 id、能力），由节点上报 | `findAgentByAlias()` | 运行进程 |
| `channels` | 6 个 IM 适配器 + Web 渠道；凭据加密；capabilities；健康 | `ChannelAdapter` 端口、`send()`、`onInbound()` | 在核心里写渠道特判 |
| `recipients` | 渠道上的身份（chat/user/group）、授权（白名单、“识别我的账号”）、静默时段 | `resolveRecipient()` | — |
| `commands` | IM/Web 指令解析与执行（`contracts/commands/im-commands.json`） | `parseCommand()` | — |
| `routing` | 绑定表（管理/通知/团队/总控）、确定性选路、回复溯源、按发送人分会话、dry-run 预览 | `route(inbound)` | 让 LLM 选渠道（MUST NOT） |
| `conversations` | 会话（稳定 id + generation + display_id + 原生 resume_id）、消息账本（append-only）、FTS 检索 | `appendMessage()`、`searchHistory()` | — |
| `delivery` | outbox、令牌桶限速、重试表、死信、能力降级渲染（IR → 渠道格式） | `enqueue()` | — |
| `approvals` | 审批请求、Y1/N1、卡片按钮、超时拒绝、held 队列 | `requestApproval()` | — |
| `orchestration` | 汇总屏障（N 来源或超时）、并发写保护租约的中转侧视图 | `openBarrier()` | 调用模型 |
| `permissions-filter` | 接收人 × 业务线 × 字段过滤与脱敏、出站前最后一道 | `filterOutbound()` | — |
| `audit` | 出站审计、管理操作审计、分身采集的“中转侧原始事件”转发 | `record()` | 存分身学习结果 |
| `notifications` | p0–p3 分级、PWA Web Push（VAPID）、渠道健康告警、备用渠道 | `notify()` | — |
| `node-gateway` | 节点 WSS 通道：鉴权、envelope、seq/ack、断线续传、心跳、背压 | `sendToNode()`、`onNodeFrame()` | — |
| `system` | 健康检查、版本、doctor、配置导入导出、急停 | — | — |

### 4.2 本机节点 `apps/node/src/modules/`
| 模块 | 职责 |
|---|---|
| `relay-link` | 同时连接 1..N 个中转（个人/公司，DEC-048）；每条连接独立凭据、独立路由命名空间；断线指数退避 + 续传 |
| `agents` | ACP Host：通用 ACP 适配器（读 ACP Registry + 本地 `InputAdapterSpec` 表）、进程监管（Windows Job Object / POSIX 进程组）、权限请求转审批、Coze HTTP 适配器、Webhook 输入（5102） |
| `sessions` | 智能体会话生命周期、`/clear`（generation+1）、resume、转录存储（JSONL + 索引）、按会话 ID 查询 |
| `workspace-guard` | 同一目录写入租约（同一时刻一个写入型智能体）或自动 git worktree（G10） |
| `models` | 用户模型配置（Provider/Base URL/Key/模型/参数/日月上限/超限动作/系统提示词）；Key 存 OS 钥匙串；用量与费用估算 |
| `supervisor` | 总控：把关分级（直回/上报/丢弃/合并）、随时对话通道（不打断执行）、任务分派、导入任务清单 |
| `meetings` | 会议：结构化事件（会议/轮次/发言/纪要/决策），主持策略“全员提交或超时” |
| `twin` | 分身数据：用户指令 + 时间线采集（v1 只采不学），查看/修改/删除/导出 |
| `local-console` | 127.0.0.1:5100 本机 API 与 `apps/web` 的 node 目标静态资源 |
| `system` | 单实例锁、doctor、恢复密钥导出、开机自启安装器、metrics |

### 4.3 共享层
- `apps/*/src/shared/`：领域原语（Entity、Result、Clock、Id）、事件总线（进程内）。
- `apps/*/src/core/`：配置读取、日志（pino，带 trace_id）、错误基类（映射 `packages/contracts/errors`）、安全（加密、钥匙串抽象）。
- 根目录白名单在 PROJECT-STRUCTURE-SPEC §5.1 基础上增加 `THIRD_PARTY_NOTICES`（DEC-033 要求；偏离已登记）。
- 只有出现 ≥2 个真实消费者才进 `packages/`（PROJECT-STRUCTURE-SPEC §12.1）：v1 只建 `contracts`、`testkit`。

## 5. 依赖方向（机器守卫）
```text
后端（relay 与 node 相同）：interfaces → application → domain ← infrastructure
前端：pages → features → components/ui → lib
跨模块：只经对方 index.ts 公开 API 或进程内领域事件
跨进程：relay ↔ node 只经 packages/contracts/protocol 的 envelope；web ↔ relay 只经 packages/contracts/api
```
守卫：dependency-cruiser + ESLint `no-restricted-imports` + `make guard`（ADR-011）。

## 6. 关键流程

### 6.1 IM → 智能体（管理模式，微信）
1. `channels/wechat` 长轮询 `getupdates` 收到文本 → 立即持久化入站事件（幂等键 = 渠道 + 平台消息 id）→ ≤3 秒内回执（若渠道支持）。
2. `recipients` 判定发送人是否授权；未授权 → 只回固定提示，不入路由（DEC-030）。
3. 解析指令（`/use`、`@别名`、`/clear` 等，见 `contracts/commands/im-commands.json`）；普通文本 → `routing.route()`：引用回复 → 溯源到原会话（G2）；否则 → 当前默认目标。
4. 若目标智能体有待答审批 → 进入 held（DEC-012）。
5. `node-gateway.sendToNode(device, frame: agent.prompt)`；设备离线 → 排队并回“设备离线，已排队”（DEC-037）。
6. 节点 `agents` 在该会话子进程上 `session/prompt`；流式更新只在节点侧聚合，按 DEC-017 只把“完成/失败/审批/阻塞”或可编辑状态卡回传。
7. 回传帧 → `conversations.appendMessage` → `permissions-filter` → `delivery.enqueue` → 渠道发送（微信额度预算器，不足则合并/降级/提示续期，DEC-023）。

### 6.2 总控模式
所有智能体输出先进入节点 `supervisor`（DEC-018，不可关）：分级 → 直接回复发起人 / 合并入摘要 / 上报给用户（输出端）/ 丢弃并记录。用户与总控的“随时对话”走独立会话，不进入执行队列，不打断任务。会议：总控创建 meeting → 向参与智能体广播轮次 → 收齐或超时 → 纪要 → 决策 → 分派任务。

### 6.3 通知模式 / 团队模式
通知：一个来源 → 绑定的多个接收人；接收人的回话按 `(route, recipient)` 建立独立会话（G25）。团队：绑定表多对多，入站只到一个目标（DEC-006）；汇总任务经 `orchestration` 屏障收齐后发出（G1）。

### 6.4 Web 控制台对话（默认渠道）
Web 是一个内置渠道 `web`：浏览器经 WSS 订阅会话事件、经 REST 发消息；与 IM 走同一路由内核与账本。PWA 安装后，p0/p1 通知经 Web Push 送达（DEC-057）。

## 7. 数据归属（谁存什么）
| 数据 | relay.db | node.db | 理由 |
|---|---|---|---|
| 账号、组织、角色、设备、项目、绑定、接收人 | ✅ | 仅智能体定义（`agent.upsert`）与 supervised 集合（`route.sync`） | 多用户控制台在中转（ADR-015） |
| IM 凭据（加密，主密钥在中转主机密钥文件/环境） | ✅ | — | IM 连接在中转 |
| IM 侧消息账本、投递、审批、审计 | ✅ | — | 审计与回复溯源 |
| 智能体完整转录、ACP 原生 session/resume id | 只存引用（会话 id、摘要） | ✅ | 代码与上下文不出本机 |
| 模型配置、API Key（钥匙串）、用量费用 | — | ✅ | DEC-044 |
| 分身数据（指令 + 时间线） | 只存审计所需 | ✅ | DEC-049 |
| 会议、总控决策记录 | 摘要与外发消息 | ✅ 全量 | 总控在本机 |

## 8. 横切关注点（每项详见 design/）
| 维度 | 设计文档 |
|---|---|
| 前端 | DESIGN-001 |
| 后端·中转 | DESIGN-002 |
| 后端·本机节点 | DESIGN-003 |
| 数据 | DESIGN-004 |
| 交互（IM 指令、审批、Web 对话） | DESIGN-005 |
| 逻辑（路由、模式、溯源、屏障） | DESIGN-006 |
| 组件（适配器、端口） | DESIGN-007 |
| 复用（依赖、移植、许可） | DESIGN-008 |
| 拓展（新增渠道/输入/版本演进） | DESIGN-009 |
| 性能 | DESIGN-010 |
| 配置 | DESIGN-011 |
| 知识库（v1 会话检索，v3 知识库） | DESIGN-012 |
| 响应 | DESIGN-013 |
| 存储 | DESIGN-014 |
| 资源 | DESIGN-015 |
| 通信协议（relay↔node、ACP、IM） | DESIGN-016 |
| 告警与通知 | DESIGN-017 |
| 异常与报告 | DESIGN-018 |
| 安全与权限 | DESIGN-019 |
| 总控 | DESIGN-020 |
| 分身数据 | DESIGN-021 |
| 模型配置与费用 | DESIGN-022 |

## 9. 已知风险（详见 `00_governance/risks.md`）
R-01 微信 context_token 24h / 约 10 条主动消息（部分确认，U-02）；R-02 ZCode 私有协议与社区桥 ToS；R-03 v1 范围大（6 IM + 13 智能体 + 总控 + 多用户）；R-04 香港访问 iLink 连通性（证据不足）；R-05 Copilot CLI ACP 为 public preview；R-06 QQ 主动消息配额文档冲突。
