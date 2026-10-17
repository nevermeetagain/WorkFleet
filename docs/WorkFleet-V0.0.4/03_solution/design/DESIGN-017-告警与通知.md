---
id: DESIGN-017
type: design
title: 告警与通知（p0–p3、渠道健康状态机、备用渠道、静默时段、Web Push、微信额度预算器）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - DEC-017/023/034/046/057
  - ADR-014
  - REQ-F-009/030/031、REQ-NF-003、U-02、U-07
  - packages/contracts/schemas/entities/channel.schema.json（health）、recipient.schema.json（quietHours）、route.schema.json（priorityFloor）、delivery.schema.json
  - packages/contracts/adapters/channel-capabilities.schema.json、channel-kinds.v1.json
  - packages/contracts/events/domain-events.json（channel.health_changed、device.offline、budget.exceeded…）
  - packages/contracts/api/relay.openapi.json（push-subscriptions、vapid-public-key、recipients PATCH）
  - database/migrations/relay/0001_init.sql（push_subscriptions、channel_tokens）
  - V0.0.2/30-协议与端点/03 §1/§6/§9、04 §6
---

# DESIGN-017：告警与通知

> 证据标签：已确认 / 部分确认 / 证据不足 / 推断 / 待实测。`notifications` 模块在中转（architecture §4.1）；节点产生的告警经 `agent.output`/`agent.status` 或 domain event 汇入中转再外发。

## 1. 两类消息
| 类 | 内容 | 走向 |
|---|---|---|
| 业务消息 | 智能体完成/失败/审批/阻塞、总控上报、汇总 | 按绑定（route）→ 接收人 |
| 系统告警 | 渠道凭据失效、额度将尽、长连接断开、设备离线、预算超限、Bot 被他处消费、急停 | **独立于绑定**，发给“告警对象”（§4.1）→ 走备用渠道（DEC-023） |

## 2. 优先级 p0–p3
| 级别 | 定义 | 投递规则 | 示例 |
|---|---|---|---|
| p0 立即 | 需要人在分钟级介入，否则系统失能或安全风险 | 立即；**无视静默时段**；可动用微信预留额度；主渠道不可用时**并行**走 Web Push + 首个健康备用 IM；不合并 | 渠道凭据失效（微信授权过期、飞书 secret 错）；长连接断开 ≥ 30 s；微信额度剩 ≤ 3（REQ-F-009/030 要求 p0）；high 风险审批；急停已执行；检测到 Bot 被他处消费（REQ-F-031） |
| p1 高 | 需要人在小时内处理 | 立即；静默时段内**延后到结束**（不合并）；主渠道不可用时走首个备用 | 普通审批；任务失败；总控上报（escalate）；模型预算超限（`budget.exceeded`）；设备离线且有排队消息 > 10 分钟；node_outbox 积压 |
| p2 普通 | 结果类信息 | 立即；静默时段延后并**合并**为一条；额度紧张时进入摘要（§6） | 任务完成（final）；Hindsight 不可用（v3）；资源 warn |
| p3 摘要 | 低价值进度/资讯 | 只进摘要（小时级或下一次入站），从不单发 | 进度变化、总控 merge 结果、p3 通知 |
- 消息优先级来源：`agent.output.priority`（节点按 DESIGN-013 §4 默认，总控可改）；系统告警由 notifications 指定。
- 路由 `priorityFloor`：低于该级的消息对该绑定 `suppressed`（route.schema.json）。系统告警不受 priorityFloor 约束。
- 审批默认 p1，`risk=high` 升 p0（V0.0.2/04 把审批定为 p0，此处细化为按风险分级；推断，可由用户改为全部 p0）。

## 3. 渠道健康状态机（`channel.health` 枚举：healthy/degraded/expired/disconnected/disabled）
```text
             enable + 凭据校验通过
 disabled ───────────────────────────▶ healthy
    ▲   ◀─────────── disable（人工）────────── 任意状态
    │
 healthy ──长连接断开/长轮询失败（首次）──▶ degraded ──30 s 内未恢复──▶ disconnected
    ▲                                         │                         │
    └──────────── 连接恢复 / 成功收发 ──────────┴─────────────────────────┘
 healthy/degraded ──401/403/凭据类错误（errorClass=auth）──▶ expired ──重新扫码/提交凭据──▶ healthy
 healthy ──限流/额度类错误（rate_limited/quota_exhausted）──▶ degraded（不升级为 disconnected）
 healthy ──微信 ret=-14（会话暂停 1 h，V0.0.2/03 §1.2）──▶ degraded，1 h 后自动探测
```
| 转移 | 告警 | 时限（REQ-F-030：60 s 内 p0） |
|---|---|---|
| → expired | p0 “{渠道} 授权已失效，请重新扫码/更新凭据” | 检测到即发（≤ 5 s） |
| → disconnected | p0 “{渠道} 连接中断” | 断开后 30 s（重连宽限）+ ≤ 5 s 发送 ≤ 60 s |
| degraded（限流/额度） | 不单独告警；额度将尽由 §6 发 p0 | — |
| → healthy（从 expired/disconnected） | p2 “已恢复” | 合并发送 |
- 每次转移：`channels.health` 更新 + domain event `channel.health_changed`（key `channelId+health+at`）+ 审计 `channel.health_changed`（actor=system）。
- 去抖：同一渠道同一告警 10 分钟内只发一次（状态持续则 1 小时提醒一次，最多 3 次，推断）。
- 探测：长连接类由 SDK 连接事件驱动；长轮询类以“轮询请求失败”驱动（网络错误连续 2 次即 degraded）；健康渠道每 10 分钟无任何收发时不主动探测（避免额外配额消耗，推断）。
- Bot 唯一消费者检测（REQ-F-031、DEC-034）：
  - Telegram：`getUpdates` 返回 409 Conflict（“terminated by other getUpdates request”，部分确认）→ p0 `BOT_IDENTITY_CONFLICT`；
  - 微信：被顶掉的表现**证据不足**（TASK-041 真机：两个客户端同时扫码/长轮询观察 ret 码）；
  - 飞书长连接为集群模式（多客户端随机一个收到，已确认）→ 无法从错误码检测；启发式：Web 渠道发出测试消息 `channels/{id}/test` 并要求用户在飞书回复，未收到则提示（推断）；
  - 跨 tenant 同一 Bot：`ux_channels_bot_identity` 唯一索引在绑定时直接阻断（0001，已确认）。

## 4. 备用渠道选择
### 4.1 告警对象
| 告警 | 对象 |
|---|---|
| 渠道健康 | 渠道所属 tenant 的 admin + 该渠道创建者 |
| 设备离线/积压、恢复密钥类 | 设备所有者（`devices.owner_user_id`） |
| 预算超限、总控降级 | 节点所有者（设备所有者） |
| 急停 | tenant 全部 admin/operator |
| Bot 冲突 | 渠道创建者 + admin |

### 4.2 选择算法（每个告警对象 user U）
```text
candidates(U, alert):
  A = push_subscriptions WHERE user_id=U AND min_priority <= alert.priority          # Web Push（DEC-057）
  B = recipients WHERE linked_user_id=U AND authorized=1 AND scope='direct'
        AND channel.health='healthy' AND channel.id != alert.channelId
        AND channel.capabilities.proactiveDirectMessages = true
        AND (proactiveQuota == null OR budget.remaining(channel, recipient) > 0)
      ORDER BY 最近一次该 recipient 入站时间 DESC                                     # 用户最近在用的 IM 优先（推断）
  C = Web 控制台横幅（始终写入，用户下次打开可见）
deliver:
  p0: A 全部 + B[0]（并行），失败则 B[1]；C
  p1: 主渠道（若健康）否则 B[0]，再否则 A；C
  p2/p3: 主渠道；不可用则留在 C，等恢复后合并
```
- “主渠道”= 告警对象在**该告警相关渠道之外**、绑定中最常用的 direct 接收人；对渠道健康告警，主渠道本身即故障渠道，因此直接走备用。
- 微信不用于向他人发告警（DEC-046）：B 仅限 `linked_user_id = U` 本人的接收人，天然满足。
- 用户自定义备用顺序：契约无字段（差异 #1），v1 使用上面的确定性排序，并在控制台展示“告警将发往：…”预览。

## 5. 静默时段（recipient.quietHours）
- 字段：`{start:"HH:mm", end:"HH:mm", tz:IANA}`（recipient.schema.json）；`start > end` 表示跨午夜（如 22:00–08:00）。
- 判定（以 recipient 的 tz 计算本地时间 t）：`inQuiet = start<=end ? (start<=t<end) : (t>=start || t<end)`；DST 切换日按 IANA 规则（用 `Intl`/Temporal polyfill，不手写偏移）。
- 行为：p0 放行；p1 → `deliveries.next_attempt_at = 静默结束时刻`，状态 `queued`；p2 → 同上并在结束时合并为一条“静默期间 N 条更新”；p3 → 进入摘要。
- 审批在静默时段内：p1 审批延后会导致超时自动拒绝 → 审批 `expiresAt` 不变（安全优先），用户醒来看到“已过期”并可在控制台重发（推断，记录为产品取舍，见差异 #2）。

## 6. 微信额度预算器（按能力：`capabilities.proactiveQuota != null` 即启用，不硬编码渠道）
### 6.1 状态
`channel_tokens(channel_id, recipient_id, token_enc, refreshed_at, sent_since_refresh)`（0001，已确认）。
参数来自 `proactiveQuota`：`maxMessagesPerInbound`（规划值 10）、`tokenTtlSec`（86400）、`windowSec`（86400）（channel-kinds.v1.json，部分确认，U-02）。
```text
remaining = max(0, maxMessagesPerInbound - sent_since_refresh)
expired   = now >= refreshed_at + tokenTtlSec*1000
入站到达   → token 更新，refreshed_at=now，sent_since_refresh=0（同一事务；入站先于任何出站处理）
每次成功发送 → sent_since_refresh += 1
```
### 6.2 预算策略
| 剩余 | 放行 | 附加 |
|---|---|---|
| > 3 | 全部按优先级正常发送（p3 仍只进摘要） | — |
| == 3 | 正常 | 本条末尾附“（额度剩 3 条，回复任意字续期）”，并发 p0 “额度将尽”到**备用渠道**（REQ-F-009/030） |
| 2 | 仅 p0、p1、final（p2） | 附续期提示；p2 非 final → 摘要 |
| 1 | 仅 p0（预留，推断：预留 1 条给 p0） | 续期提示 |
| 0 或 expired | 不发；`CHANNEL_QUOTA_EXHAUSTED` | p0/p1 → 备用渠道（§4.2）；其余进摘要，等下一次入站时先发摘要（1 条） |
- 摘要发送遵守同一预算（DESIGN-013 §5）。
- 入站到达时的发送顺序：①该入站的回执/结果 ②积压摘要（合并为 1 条）③被延后的 p1（每条消耗 1 额度）。
- 绝不跨账号/跨接收人复用 context_token（V0.0.2/03 §1.3，社区插件明确禁止）。
- U-02 分支：若真机证实无额度限制 → 渠道能力 `proactiveQuota=null` → 预算器自动关闭，其余逻辑不变（product-requirements §7）。
- 发送失败 `ret=-2`（缺/过期 token）→ 视同 expired，置 `sent_since_refresh=max` 并按“0”处理（部分确认）。

## 7. Web Push（ADR-014、DEC-057）
| 项 | 设计 |
|---|---|
| 协议 | Web Push（RFC 8030）+ 消息加密（RFC 8291，aes128gcm）+ VAPID（RFC 8292） |
| 密钥 | VAPID P-256 密钥对，中转首次启动生成，私钥加密保存（DESIGN-014 §3.1）；公钥经 `GET /api/v1/push/vapid-public-key` |
| 订阅 | `POST /api/v1/push-subscriptions{endpoint, keys{p256dh, auth}, minPriority}`（默认 minPriority=p1，0001 默认值） |
| 发送头 | `TTL`：p0 86400、p1 21600、p2 3600；`Urgency`：p0 high、p1 high、p2 normal、p3 不推送；`Topic`：`apr-{approvalId}` / `chn-{channelId}`（同主题新消息替换旧消息，减少堆积） |
| 负载 | ≤ 3 KiB 明文 JSON：`{title, body(≤120 字), url:"/c/{conversationId}"|"/approvals/{id}", priority, traceId}`；**不放敏感正文**（推送服务商虽只见密文，锁屏可见；推断） |
| 失败 | 404/410 → 删除订阅；其他错误 `failed_count+1`，≥ 5 次连续失败删除；429/5xx 按 DESIGN-018 IM 发送重试表 |
| 客户端 | Service Worker `push` 事件 → `showNotification`；点击打开 url；审批通知提供“打开审批”而非直接按钮决策（避免误触；推断） |
| iOS | 需 iOS 16.4+ 且“添加到主屏幕”的 PWA 才能订阅（部分确认，U-07，TASK-203 实测） |

## 8. 数据与接口
- 告警记录：v1 复用 `messages`（direction=system，author.kind=system）写入用户的“系统通知会话”（每用户一个 Web 渠道会话，displayId 前缀 `SYS-`，推断）+ `deliveries` 走同一 outbox；不新建表（避免第二套投递）。
- 节点侧告警（预算超限、资源）：节点发 `agent.output{kind:error|status, priority}` 到总控/系统会话（需要会话 id，见 DESIGN-022 差异 #4）。
- 指标：`wf_alert_sent_total{priority,via="push|im|banner"}`、`wf_channel_health{channel,state}`、`wf_wechat_quota_remaining{channel,recipient}`（仅计数，不含身份明文）、`wf_alert_latency_ms`（事件到发送）。

## 9. 测试
- 状态机：FakeChannel 注入断开 → 30 s degraded → disconnected，断言 p0 在 60 s 内到达 FakePush/备用 FakeChannel（REQ-F-030）。
- 预算器：10 条配额逐条发送，第 7 条（剩 3）附续期提示且触发 p0；剩 1 时 p2 进入摘要；入站后摘要先发。
- 静默：22:00–08:00 Asia/Shanghai，23:00 的 p1 在 08:00 发出，p0 立即。
- Web Push：410 删除订阅。

## 10. 与契约的差异 / 待办
1. 无“用户级备用渠道顺序/告警偏好”字段与 API → 建议 `user.notificationPrefs{fallbackOrder[], quietHours}` 或独立资源。
2. 静默时段只在 recipient 上，用户级（跨渠道）静默与 Web Push 静默无处配置；审批在静默期过期的取舍需用户确认。
3. 契约无系统通知会话/告警实体；本文复用 messages + deliveries，`author.kind=system`。
4. `channel-capabilities` 无“typing”“被动回复窗口”能力（见 DESIGN-013 差异）；额度预算器只覆盖 `proactiveQuota` 模型，QQ“每好友每天 1000 条/用户可关闭”无法表达（文档冲突 R-06）→ 建议 `dailyCapPerRecipient`。
5. domain-events 无 `notification.sent`、`quota.low` 事件 → 指标与审计可用，但订阅方无法解耦；建议补充。
