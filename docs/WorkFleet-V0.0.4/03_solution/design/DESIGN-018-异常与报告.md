---
id: DESIGN-018
type: design
title: 异常与报告（三类重试表、死信与重放、熔断、急停、IR 汇报渲染、错误码规范、trace_id、运行日志与审计）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - DEC-011/013/024/030/043
  - REQ-F-028/033、REQ-NF-003/007、G9
  - packages/contracts/errors/error-codes.json、schemas/common/error.schema.json
  - packages/contracts/schemas/entities/message-body.schema.json、delivery.schema.json、audit-entry.schema.json
  - packages/contracts/protocol/frames/emergency.stop|emergency.resume|error.schema.json
  - packages/contracts/api/relay.openapi.json（deliveries、deliveries/{id}/replay、emergency/*、audit）
  - packages/contracts/schemas/entities/model-profile.schema.json（params.retries/timeoutSec）
  - database/migrations/relay/0001_init.sql（deliveries、tenants.emergency_stopped_at、audit_log）
  - V0.0.2/30-协议与端点/04 §4（errorClass 归一化）、§6
  - V0.0.3/03_solution/analysis-18-dimensions.md §18
---

# DESIGN-018：异常与报告

> 证据标签：已确认 / 部分确认 / 证据不足 / 推断 / 待实测。

## 1. 错误分类（统一 errorClass）
所有适配器（IM、模型、输入）把底层错误归一化为（V0.0.2/04 §4 `SendReceipt.errorClass`）：
`rate_limited | window_expired | quota_exhausted | auth | forbidden | transient | fatal | timeout`
| errorClass | 对外错误码（error-codes.json） | 是否重试 |
|---|---|---|
| rate_limited | RATE_LIMITED | 是，遵守 `retryAfter` |
| window_expired / quota_exhausted | CHANNEL_QUOTA_EXHAUSTED | 不在同渠道重试 → 备用渠道/摘要（DESIGN-017 §6） |
| auth | CHANNEL_CREDENTIAL_EXPIRED / MODEL_PROVIDER_ERROR | 否；渠道置 expired，投递挂起 |
| forbidden | FORBIDDEN / RECIPIENT_UNAUTHORIZED | 否 → 死信 |
| transient / timeout | INTERNAL / MODEL_PROVIDER_ERROR / AGENT_UNAVAILABLE | 是 |
| fatal | CHANNEL_CAPABILITY_UNSUPPORTED / VALIDATION_FAILED / PAYLOAD_TOO_LARGE | 否 → 死信 |

## 2. 三类重试表（DEC-024：交互类首次延迟 ≤ 2 s）
退避通式：`delay_n = min(cap, base × factor^(n-1)) × jitter(0.8–1.2)`；若有 `retryAfter` 则 `delay = max(delay_n, retryAfter)`。

### 2.1 IM 发送（中转 delivery）
| 类别 | 适用 | 最大尝试 | 延迟序列（秒） | 总时限 | 失败后 |
|---|---|---|---|---|---|
| 交互类 | 回执、审批卡、/命令回复、p0 告警 | 4 | 1, 2, 4 | 30 s | p0 → 备用渠道；其余 → dead |
| 结果类 | final/error/digest（p1/p2） | 6 | 2, 5, 15, 60, 300 | 30 min | dead + p1“投递失败” |
| 批量类（v2 推送团队预留） | p3/通知模式群发 | 8 | 5, 15, 60, 300, 900, 1800, 3600 | 3 h | dead |
- `rate_limited` 不计入尝试次数，但总时限仍有效（推断，避免 429 风暴下过早进死信）。
- `auth`：delivery 保持 `queued`（不计次）直到渠道恢复 healthy 或 7 天后 → dead（凭据修复后自动续发，推断）。
- 编辑类（状态卡更新）：不重试（DESIGN-013 §3.2）。
- 实现：`deliveries.status/attempts/next_attempt_at/last_error`（0001）；worker 轮询 `ix_deliveries_due`，内存唤醒信号加速（DEC-013）。

### 2.2 模型调用（节点 models / 总控）
| 项 | 值 | 依据 |
|---|---|---|
| 最大重试 | `model-profile.params.retries`（0–5，默认 2） | 契约 |
| 单次超时 | `params.timeoutSec`（5–600，默认 30） | 契约 |
| 延迟 | 1 s, 3 s（交互：/boss 对话、把关）；后台（会议纪要）2 s, 8 s, 30 s | DEC-024 |
| 可重试 | 429（遵守 `retry-after`，上限 30 s）、5xx、网络错误、超时 | 推断 |
| 不重试 | 400/401/403/404/422 | — |
| 失败后 | 把关：该条走规则降级（DESIGN-020 §3）；/boss：回复“模型暂不可用”+ `MODEL_PROVIDER_ERROR` | ADR-013 |

### 2.3 输入适配器（节点 agents）
| 场景 | 重试 | 失败后 |
|---|---|---|
| spawn / initialize 失败 | 2 次：1 s、5 s | `AGENT_UNAVAILABLE`，agent.status=unavailable，p1 |
| 轮次中子进程崩溃 | 自动重启 1 次并 `session/resume|load`，**不自动重放**该 prompt（避免重复写操作），提示用户“已恢复会话，请确认是否重试” | p1 |
| 监督放弃 | 15 分钟内重启 ≥ 6 次（OR supervise 模式，analysis §18） | agent.status=error，停止自动重启，p1；需用户 /status 或控制台“重新启用” |
| Coze HTTP（v1，REQ-F-008、DEC-055） | 同 §2.2 模型表参数（超时 30 s、重试 2 次：1 s、3 s） | `AGENT_UNAVAILABLE`，p1 |
| Webhook 输入（5102） | 不重试（调用方负责）；返回 202/4xx/423 | — |

### 2.4 中转↔节点帧
无限重试（outbox + 续传，DESIGN-016 §3/§4）；不进死信；积压 > 7 天 p1。

## 3. 死信与重放
- 死信 = `deliveries.status='dead'`（0001）。控制台 `GET /api/v1/deliveries`（audit.read，含死信）展示 `lastError`、尝试次数、渠道、接收人、`renderedAs`。
- 重放 `POST /api/v1/deliveries/{id}/replay`（权限 `channel.write`）：
```text
replay(deliveryId, principal):
  d = deliveries[id]; assert d.status == 'dead'           else 409 CONFLICT
  assert tenant 未急停                                     else 423 EMERGENCY_STOPPED
  assert channel.health in (healthy, degraded)            else 409 CHANNEL_CREDENTIAL_EXPIRED
  重新执行 filterOutbound（过滤规则可能已变）→ 重新渲染
  UPDATE status='queued', attempts=0, next_attempt_at=now, last_error=NULL
  audit('delivery.replayed', actor=principal, detail{prevError})
```
- 同一 deliveryId 复用，`ux_deliveries(message_id, recipient_id)` 保证不产生第二条投递；平台侧是否重复由“dead 前从未成功”保证（dead 只来自失败）。
- 死信保留 30 天（DESIGN-014 §7）。

## 4. 熔断
| 对象 | 打开条件 | 打开时长 | 半开 | 打开期间行为 |
|---|---|---|---|---|
| 渠道（每 channelId） | 60 s 内 ≥ 10 次发送失败且失败率 ≥ 50%（排除 rate_limited） | 60 s，连续打开时翻倍至 15 min | 放行 1 条探测 | 投递保持 queued；健康转 degraded（DESIGN-017 §3） |
| 模型配置（每 modelProfileId） | 120 s 内连续 5 次失败 | 60 s → 最长 10 min | 1 次请求 | 总控走规则降级（DESIGN-020 §3），不计费用 |
| 输入适配器（每 agentId） | 见 §2.3 监督放弃 | 直到人工恢复 | — | 拒绝新 prompt：AGENT_UNAVAILABLE |
| Web Push 端点 | 连续 5 次失败 | 删除订阅 | — | DESIGN-017 §7 |
状态在内存（进程重启即复位，推断可接受）；`/metrics` 暴露 `wf_circuit_state{kind,id}`。

## 5. 急停（REQ-F-033、G9：/stop all 5 秒内冻结）
### 5.1 触发
IM `/stop all`（权限 `emergency.stop_all`）或 `POST /api/v1/emergency/stop-all{reason}`（202）。
```text
T0 中转（同一事务）：tenants.emergency_stopped_at = now；audit('emergency.stopped')；domain event emergency.stopped
T0+ 中转内存标志 tenantStopped=true（所有模块读取，O(1)）
   ├ delivery worker：该 tenant 的投递不再取出发送（保持 queued，“冻结”）；正在 sending 的一条允许完成
   ├ routing：新入站正常入账本，但不下发 agent.prompt；IM 回“已急停，消息已记录”（EMERGENCY_STOPPED ui）
   ├ approvals：待审批全部置 cancelled，通知节点（由 emergency.stop 驱动）
   └ 对 tenant 内每台设备追加 emergency.stop{reason} 帧（优先发送：新帧在 outbox 尾部，但在线设备积压通常很小）
T0+≤2 s 节点：session/cancel 全部进行中轮次；Scheduler 暂停；pending_permissions 全部回 cancelled；
          总控停止 LLM 调用与会议计时器；Webhook 5102 返回 423；回 agent.status{stopped}
T0+≤5 s 中转：收到全部在线设备的 stopped 状态 → 控制台全局红色横幅（EMERGENCY_STOPPED ui）；p0 通知 admin/operator
```
- 5 s 预算：中转本地动作 < 100 ms；帧 RTT 跨境 ≤ 2 s（REQ-NF-001，部分确认）；ACP cancel 为通知，进程不响应时节点在 10 s 后结束进程——**“冻结”以停止出站与停止下发为准**，进程清理可晚于 5 s（推断，验收口径需确认，差异 #1）。
- 离线设备：重连续传时，outbox 中位于 emergency.stop 之前的 agent.prompt 会先到达。缓解：节点在 welcome 后进入 **2 s 续传静默窗**——窗口内收到的 prompt 只入队不执行；窗口内若收到 emergency.stop 则一并冻结（推断；根治需 `welcome.emergencyStopped`，DESIGN-016 差异 #6）。另外中转在急停时把该 tenant 所有设备 outbox 中**未 ack 的 agent.prompt** 标记为“急停前”，节点处理到 emergency.stop 时会取消它们（队列整体冻结）。

### 5.2 恢复
`POST /api/v1/emergency/resume`（`emergency.resume`，仅 admin）：
- `tenants.emergency_stopped_at = NULL`；发 `emergency.resume{}`；audit `emergency.resumed`。
- 冻结的投递：p0/p1 立即发送；p2/p3 合并为一条“急停期间 N 条更新”摘要（避免恢复瞬间刷屏，推断）。
- 冻结的 prompt（节点 prompt_queue 中 state=queued）：**不自动执行**，标记 `cancelled`，向发起人回一条“急停期间的 N 条指令已取消，可在控制台一键重发”（安全优先：指令可能已过时；推断，需用户确认，差异 #2）。

## 6. IR 汇报渲染（DEC-024；message-body.schema.json 小 IR）
渲染器 `render(body, capabilities, ctx) → { renderedAs: 'card'|'markdown'|'text'|'digest', parts: PlatformPayload[] }`，降级链 `card → markdown → text`，只依据 capabilities（DEC-008）。

| 块 | card（cards=true） | markdown（markdown=true） | text |
|---|---|---|---|
| heading | 卡片标题/分节 | `#`×level | 【标题】 |
| paragraph | 文本元素 | 原文（转义渠道特殊字符） | 原文 |
| list | 列表元素 | `- ` / `1. ` | `• ` / `1) ` |
| code | 代码块元素 | ```lang …``` | 缩进 4 空格；> 50 行折叠为“代码 N 行，详见控制台” |
| table | 卡片表格（列 ≤ 10） | Markdown 表（若渠道支持表格；否则等宽） | 每行 `列1: 值 / 列2: 值` |
| callout | 带颜色提示条 | `> ⚠️ ` 前缀（tone→emoji：info ℹ️ warn ⚠️ error ❌ success ✅） | `[警告] ` 前缀 |
| kpi | 指标组件 | `**label**: value (delta)` | `label: value (delta)` |
| attachment | 文件消息（attachments=true）| 链接（签名 URL 需会话，IM 内给控制台链接） | `附件：name（控制台查看）` |
| approval | 按钮组（buttons=true） | 文本 + `Y{n} / N{n}` 口令 | 同左 |
| status_card | 状态卡（editMessage=true 可编辑） | `[运行中 40%] title` | 同左 |
- 前缀：`tags`（如 `[项目A/z1]`）置于首行（V0.0.2/04 §5 管理模式来源标识）。
- 长度：按 `maxMessageChars` 在块边界切分；单块超长在段落/行边界切；最多 5 段，剩余“详见控制台 {displayId}”（推断）。
- 字段过滤与脱敏（`body.fields` + filter-rule）在渲染**之前**由 `permissions-filter` 执行（DEC-024“外发前脱敏”，DESIGN-019 §7）。
- 渲染结果存 `deliveries.rendered_payload`（便于审计与重放）。
- 日报/周报（v2 定时任务）沿用同一子集：heading/paragraph/list/table/callout/kpi（analysis §18）。

## 7. 错误码使用规范
1. **唯一源**：只使用 `errors/error-codes.json` 中的 code；新增须走契约变更（ADR-002）。代码中以生成的常量引用，禁止字符串字面量（ESLint 规则）。
2. **HTTP**：响应状态 = 契约 `httpStatus`；体 = `schemas/common/error.schema.json`（含 `traceId`）。
3. **帧**：`error.code` 同一集合；`refSeq` 指向引发帧。
4. **IM**：用户可见文案取契约 `ui` 列对应的 i18n 资源（REQ-NF-011），附 `traceId` 后 6 位便于报障（推断）；不回显内部堆栈。
5. **retryable**：前端/客户端只依据契约 `retryable` 决定是否显示“重试”（ux-states error 态）。
6. **跨租户**：资源不存在与无权访问一律 `NOT_FOUND`（forbiddenPaths #1）；同租户角色不足 `FORBIDDEN`。
7. **内部异常**：未分类异常映射 `INTERNAL`（500，retryable），日志记录完整堆栈 + traceId。
8. **领域错误类**：`class WfError extends Error { code: ErrorCode; details?: object; cause? }`（`core/errors`），各层只抛 WfError 或原生错误，interfaces 层统一映射。

## 8. trace_id 贯穿（REQ-NF-007）
| 入口 | 生成 | 传递 |
|---|---|---|
| Web 请求 | 中转 Fastify `onRequest`：若请求头 `X-Trace-Id` 合法（`^trc_[0-9A-HJKMNP-TV-Z]{26}$`）则沿用，否则新生成 | 响应头 `X-Trace-Id`；错误体 `traceId` |
| IM 入站 | channels 适配器收到事件即生成 | message → routing → frame |
| Webhook 输入 / 节点本地触发（总控会议、定时器） | 节点生成 | frame.traceId |
| 中转→节点 / 节点→中转 | `envelope.traceId`（必填） | 节点继续用于 ACP 调用与转录行 |
| 节点→ACP | 写入转录 `traceId`；JSON-RPC 请求 `_meta.traceId`（ACP 扩展字段，部分确认：是否被各智能体忽略待实测，不依赖其回传） | — |
| 外发投递 | delivery 日志、`audit_log.trace_id` | — |
- 日志：pino `mixin` 从 AsyncLocalStorage 取 `traceId` 自动附加；跨异步队列（delivery worker、Scheduler）从数据行恢复 traceId 后 `als.run()`。
- 一个用户动作衍生多条消息（如团队模式汇总）时，子动作沿用父 traceId（推断，便于全链路检索）。

## 9. 运行日志 vs 审计（glossary：审计 ≠ 日志）
| 维度 | 运行日志（log） | 审计（audit entry） |
|---|---|---|
| 目的 | 排障、性能 | 合规追溯：谁对什么做了什么、消息发给谁 |
| 存放 | 中转 stdout→journald；节点 `logs/` 文件 | 中转 `audit_log`（append-only，触发器禁止 UPDATE/DELETE） |
| 格式 | pino JSON：`level, time, traceId, module, msg, …` | audit-entry.schema.json |
| 内容限制 | **不得**含：消息正文、IM 凭据、令牌、模型 Key、密码（pino `redact`：`req.headers.authorization`、`*.apiKey`、`*.token`、`*.credential`、`*.password`、`body.blocks`）；正文只记长度与 hash 前 8 位 | 只记元数据与过滤结果，不存正文（正文在 messages 账本） |
| 保留 | 14 天（节点）/ journald 策略（中转） | 永久（DESIGN-014 差异 #3） |
| 写入方 | 任何模块 | 只经 `audit.record()` |
| 示例 | `delivery attempt failed errorClass=rate_limited retryAfter=3` | `delivery.sent {messageId, recipientId, channelId, sourceAgentId, filtersApplied[]}` |
必须审计的动作（REQ-F-028）：`delivery.sent`、`delivery.replayed`、`route.created|updated|deleted`、`filter.*`、`member.*`、`device.paired|revoked|token_rotated|primary_set`、`channel.credential_bound|health_changed|deleted`、`recipient.authorized|unauthorized|bound`、`approval.decided`、`emergency.stopped|resumed`、`config.imported`、`auth.login|login_failed|totp_enabled`。

## 10. 与契约的差异 / 待办
1. REQ-F-033 “5 秒内冻结”的验收口径（停止下发与出站 vs 进程全部退出）需确认；本文以前者为准。
2. 急停期间排队指令在恢复后“取消而非执行”为本文取舍，需用户确认。
3. error-codes 缺：`CIRCUIT_OPEN`（熔断打开时对 Web 的明确提示，现用 `MODEL_PROVIDER_ERROR`/`CHANNEL_CREDENTIAL_EXPIRED` 近似）、`PROTOCOL_SEQ_GAP`、`AGENT_CRASHED`（与 AGENT_UNAVAILABLE 区分）。
4. audit-entry `actor.kind` 无 `agent`/`supervisor`，总控自动动作只能记 `system` 或 `device` → 建议补充。
5. openapi `/api/v1/deliveries` 无 `status=dead` 过滤参数 → 建议补 `status`、`channelId`、时间范围参数。
6. 契约未规定 `X-Trace-Id` 请求/响应头 → 建议在 openapi 公共参数中声明。
