---
id: DESIGN-009
type: design
title: 拓展详细设计（新增渠道/ACP 智能体/模式的步骤；v2–v4 路线图挂载点；插件进程外化）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - "DEC-007"
  - "DEC-008"
  - "DEC-015"
  - "DEC-026"
  - "DEC-045"
  - "DEC-046"
  - "DEC-049"
  - "ADR-002"
  - "ADR-003"
  - "ADR-007"
  - "ADR-010"
  - "REQ-NF-008"
  - "PRB §5 MUST NOT #8"
  - "02_requirements/backlog.md（BL-001…011）"
  - "packages/contracts/adapters/**"
  - "packages/contracts/schemas/entities/route.schema.json"
  - "DESIGN-002"
  - "DESIGN-003"
  - "DESIGN-006"
  - "DESIGN-007"
  - "V0.0.3/analysis-18-dimensions §9"
---

# DESIGN-009 拓展

> 目标（REQ-NF-008）：新增一个 IM = 新增一个渠道适配器目录 + 注册一行，核心零改动；新增一个 ACP 智能体 = 一条 spec + 一个夹具。v1 明确不做的（MUST NOT #8）在本文只给挂载点，不实现。

## 1. 新增渠道（输出端）步骤清单
| 步 | 动作 | 文件/位置 | 所有者 | 依据 |
|---|---|---|---|---|
| 1 | 许可与平台事实调研：入站方式（长连接/长轮询/stream）、是否需公网回调、按钮/卡片/编辑/引用能力、速率与主动消息限额；**不确定项标“证据不足”** | `docs/…/02_requirements` 新 REQ + 证据 EVD | 规划/Agent-Docs | ADR-010 |
| 2 | 在契约渠道清单追加一条 kind 与默认能力（字段齐全，符合 channel-capabilities.schema） | `packages/contracts/adapters/channel-kinds.v1.json` | Agent-Contract（契约变更任务） | ADR-002；DESIGN-007 P-1 |
| 3 | 新建适配器目录：`index.ts`（Factory：kind、configSchema、credentialSchema、defaultCapabilities）、`client.ts`、`inbound.ts`、`render.ts`、`capabilities.ts` | `apps/relay/src/modules/channels/infrastructure/adapters/<kind>/` | Agent-Channel | DESIGN-007 §2 |
| 4 | 注册一行：`registry.register(<kind>Factory)` | `channels/infrastructure/adapters/index.ts`（注册表文件） | Agent-Channel | DEC-008 |
| 5 | FakeChannel 方言 + 录制夹具 | `packages/testkit/fixtures/channels/<kind>/` | Agent-QA | DEC-029 |
| 6 | 通过渠道一致性测试套件（幂等发送、长文本、按钮回调、凭据失效、停止） | `tests/integration/channels/` | Agent-QA | TASK-126 |
| 7 | 真机冒烟 + 实测能力回写契约清单 | EVD 目录 | Agent-Channel | — |
| 8 | 依赖许可写 THIRD_PARTY_NOTICES | 根目录 | Agent-Guard | DESIGN-008 §5 |
**不需要改动**：routing、delivery、approvals、前端（表单由 configSchema 渲染，DEC-010）、数据库（kind 无 CHECK，DEC-008）。若发现必须改核心，说明能力模型缺字段 → 走契约变更（新增 capabilities 字段）而非写渠道特判。

## 2. 新增 ACP 智能体（输入端）步骤清单
| 步 | 动作 | 位置 | 依据 |
|---|---|---|---|
| 1 | 确认其在 ACP 官方 Registry/文档中的启动方式、认证方式、是否支持 loadSession、是否有私有扩展 | 证据 EVD | ADR-007 |
| 2 | 追加一行 `InputAdapterSpec`：adapterId、displayName、family=acp、source、experimental、launch（command/args/windowsCommand/env/cwdMode）、detect（versionCommand/minVersion）、auth、dialect、supportsLoadSession、supportsWriteTools、configSchema、docsUrl | `packages/contracts/adapters/input-adapters.v1.json`（契约）；节点本地覆盖表 `apps/node/src/modules/agents/infrastructure/specs/<group>/` | DEC-007 |
| 3 | 若有偏差：实现 `AcpDialect`（只做必要钩子） | `apps/node/src/modules/agents/infrastructure/dialects/<id>/` | DESIGN-007 §3 |
| 4 | 录制夹具：initialize → session/new → 一轮含工具调用与权限请求的 prompt → cancel | `packages/testkit/fixtures/acp/<adapterId>/` | DEC-029、REQ-F-007 |
| 5 | 冒烟矩阵登记结论（成功/失败原因；实验项允许失败） | TASK-087 证据 | REQ-F-007 |
**零改动**：中转（`GET /adapters/input` 透传节点探测）、前端（configSchema 表单）、数据库（adapter_id 无 CHECK）。
非 ACP 新来源（类似 Coze/Webhook）= 新增一个 `family` 枚举值 → **契约变更**（input-adapter-spec.schema 的 family enum）+ 一个 `InputAdapter` 实现目录。

## 3. 新增模式（路由模式）步骤清单
模式是核心语义，**必然**触及契约与核心，不属于“零改动”扩展：
1. ADR：说明新模式解决什么、与 DEC-005/006 的关系（不得引入 LLM 选渠道、不得默认广播）。
2. 契约：`route.schema.json` 的 `mode` 枚举 + 结构约束描述；`errors` 如需新码。
3. 迁移：`routes.mode` 有 `CHECK IN (…)` → Agent-Data 新迁移重建约束（SQLite 改 CHECK 需建新表复制，按 DESIGN-004 §5 仅追加规则执行）。
4. 代码：`routing/domain/modes/<mode>.ts` 实现三个函数 `validate(route)`、`pickInbound(route, ctx)`、`targetsOutbound(route, conv, out)`；在 `pickModeDefault` 的确定性排序表中登记优先级（DESIGN-006 §4.2）。
5. 前端：`features/routes/modes/<mode>.ts` 提供模式说明与表单约束（ModePicker）。
6. 测试：DESIGN-006 §9 的路由矩阵追加该模式的全部行；dry-run 用例。

## 4. 路线图功能挂载点（v2–v4，backlog.md）
| BL | 功能 | 版本 | 挂到哪里 | 需要的契约/迁移变化 | 现在为它预留了什么 |
|---|---|---|---|---|---|
| BL-001 | 定时任务（一次/每日/工作日/休息日/每周/每月，含调休） | v2 | 新模块 `apps/node/src/modules/schedules/`（在节点触发：任务的执行者是本机智能体，DEC-037）；中转只存“定时任务元数据与审计”或完全不存（待决） | 新实体 `schedule.schema.json`；node 迁移 `schedules`、`schedule_runs`；节假日数据源内置 + 控制台修正（DEC-026） | 触发结果走普通 `agent.prompt` 等价的本地入队（`prompt_queue`），出站走现有绑定；无需改路由 |
| BL-002/003 | 推送团队与订阅/退订；每日 9:00 资讯推送（≤1 万订阅者，DEC-046） | v2 | 中转新模块 `broadcast`：订阅者名单 = 一组 recipients（`scope=channel` 或 direct）；推送 = notification 模式的大扇出 | 新实体 `audience`、`subscription`；迁移 `audiences`、`audience_members`；`/subscribe`、`/unsubscribe` 指令进 im-commands.json | delivery 的令牌桶、批量 ≤50、背压（DESIGN-010 §5–§7）；微信禁止群发校验已在绑定层（DESIGN-006 §4.1） |
| BL-004 | 异常阈值（REQ-F-036） | v2 | 绑定上的规则：`route` 增加 `thresholds`；在 fanout 前对 `message-body.fields`（kpi/字段）求值，越线升 p0 | route.schema 增字段；迁移加列 | IR 已有 `fields` 与 `kpi` 块（message-body.schema） |
| BL-005 | 总控 AGENTS.md 与 Skills 配置/上传 | v3 | 节点 `supervisor`：`supervisor_settings` 扩展 `skills`；文件存 `<dataDir>/supervisor/skills/`，不上传中转 | node-local API 新端点（上传/列表/删除）；node 迁移 | `system_prompt` 已可配（DEC-045 v1 保留） |
| BL-006 | 知识库（项目设计、目录结构图谱、上下文记忆） | v3 | 节点新模块 `knowledge`（数据不出本机）；可选外接 Hindsight（DEC-015，不可用时降级、不阻断路由） | 新端口 `KnowledgeProvider{recall(query), retain(doc)}`；node 迁移或外部服务配置 | v1 会话检索（FTS trigram，两侧）即第一阶段；`history.query` 帧可复用为检索通道 |
| BL-007 | 分身学习 loop | v4+ | 节点 `twin`：在 `twin_events` 之上新增 `twin_artifacts`（提示词模板、决策偏好、流程模板），供总控调用 | node 迁移；node-local API | v1 已采集（DEC-049）；事件 kind 已含 instruction/approval/correction/decision_point |
| BL-008 | 多级汇总、飞书多维表格输入 | v4+ | 多级汇总 = 屏障的输出作为上一级屏障的来源（需“系统来源”概念）；多维表格 = 新 InputAdapter family | barrier.schema 允许 system 来源；input-adapter family 枚举 | 屏障汇总消息 `author.kind='system'` 已入账本 |
| BL-009 | 第三方登录（OAuth） | v2 | 中转 `identity` 新增 `oauth` 应用服务与 `user_identities` 表 | openapi 新端点；迁移 | 会话机制（Cookie）不变（ADR-006） |
| BL-010 | 中转 PostgreSQL 与多实例 | 触发条件见 ADR-003 | 仓储层换 Kysely 方言；“表即队列”改 `FOR UPDATE SKIP LOCKED`；节点通道需粘性路由或跨实例转发 | 迁移改写为 PG 方言（另一目录） | 所有 SQL 经 Kysely；无 SQLite 专有语法散落在应用层（FTS 例外，需替换为 PG 全文或 pg_trgm） |
| BL-011 | 英文界面 | v2 | i18n `en-US` 资源补译 | 无 | 文案已集中（DESIGN-001 §11） |

## 5. 版本演进中的兼容规则
- 契约：`$id` 前缀含 `/v1/`；向后兼容的变更（加可选字段、加枚举值时提供降级）留在 v1；破坏性变更开 `/v2/` 并行一段时间（ADR-002）。
- 协议：`hello.protocolVersion`（当前 const 1）；中转同时支持 N 与 N-1，低于 N-1 回 `PROTOCOL_VERSION_UNSUPPORTED`（426）提示节点升级。
- 数据：仅追加迁移（DESIGN-004 §5）。
- 新帧类型：旧节点收到未知 `type` 必须回 `error{code:'VALIDATION_FAILED'}` 并 ack（不断线），使中转可按能力降级——**当前 envelope 的 type 为封闭枚举，旧节点 ajv 校验会直接拒绝**，因此新增帧必须配合 protocolVersion 升级（§7 X-2）。

## 6. 插件进程外化迁移路径（DEC-008：v1 进程内、接口可迁出）
| 阶段 | 形态 | 触发条件 | 改动 |
|---|---|---|---|
| P0（v1） | 渠道适配器、输入适配器、方言均为进程内模块，静态注册 | — | 端口方法全部 JSON 可序列化（DESIGN-007 §1） |
| P1 | “第三方渠道包”：npm 包导出 `ChannelAdapterFactory`，中转启动时按配置 `WF_CHANNEL_PLUGINS` 动态 import | 出现非核心团队维护的渠道 | 注册表支持动态加载；包须声明 `workfleet.apiVersion` 与许可；仍在主进程 |
| P2 | 进程外 worker：每个插件一个子进程（Node `child_process.fork` 或独立可执行），主进程以 **JSON-RPC over stdio** 代理 `ChannelAdapter` 方法；`emitInbound/emitHealth` 反向通知 | 插件崩溃影响主进程、或需要非 Node 语言实现、或安全隔离要求 | 新增 `PluginHost`：心跳、崩溃重启（退避 + 6 次/15 分钟放弃，DEC-021）、能力门控（manifest 声明需要的权限：网络域名、文件路径）；适配器内部无需改写（同一接口） |
| P3 | 输入端同理（InputAdapter 外置），ACP 智能体本就是外部进程，主要外置的是方言与非 ACP 适配器 | 同上 | 同上 |
- 迁移不变量：渠道/输入的数据（凭据、游标、令牌）仍由主进程持有，通过 `CredentialVault`/`CursorStore`/`ChannelTokenStore` 的 RPC 访问，插件不直接打开数据库（借鉴 Paperclip PLUGIN_SPEC 的能力门控思路，V0.0.2/12 #9，设计借鉴）。

## 7. 与契约的差异 / 待办
| # | 发现 | 处理 |
|---|---|---|
| X-1 | `routes.mode` 用 CHECK 枚举，新增模式需重建表；`agents.kind` 无 CHECK 但契约 agent.schema `kind` 为封闭枚举 | 接受（模式属于核心语义）；agent kind 新增同样需契约变更 |
| X-2 | envelope `type` 为封闭 enum，旧节点无法优雅忽略新帧 | 新帧必须随 protocolVersion 升级；建议契约允许未知 type 并规定“回 error 不断线” |
| X-3 | backlog 中定时任务的执行侧（中转或节点）未裁定 | 本文推荐节点侧（执行者在本机、离线时不触发并在上线后按 catch-up 策略补跑）；需用户/规划确认 |
| X-4 | DEC-045 要求的 `04_planning/roadmap.md` 当前不存在 | 以 backlog.md 为准；建议 Agent-Docs 补 roadmap |
