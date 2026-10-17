---
id: DESIGN-006
type: design
title: 逻辑详细设计（路由算法、四种模式、汇总屏障、按发送人分会话、dry-run）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - "WF-ARCH §6"
  - "DEC-005"
  - "DEC-006"
  - "DEC-012"
  - "DEC-018"
  - "DEC-046"
  - "DEC-053"
  - "REQ-F-005/016/017/020/021/022/023/033"
  - "packages/contracts/schemas/entities/{route,conversation,message,barrier,approval,recipient,agent}.schema.json"
  - "packages/contracts/protocol/frames/{agent.prompt,agent.output,barrier.submit}.schema.json"
  - "packages/contracts/api/relay.openapi.json（routes/dry-run、barriers）"
  - "packages/contracts/commands/im-commands.json"
  - "database/migrations/relay/0001_init.sql"
  - "glossary.md"
---

# DESIGN-006 逻辑

> 硬约束：**选路完全由绑定表与确定性规则决定，LLM 不参与选渠道**（DEC-005、MUST NOT #2）；**团队模式绝不广播入站**（DEC-006、MUST NOT #3）。所有函数在 `apps/relay/src/modules/routing/` 实现为纯领域逻辑 + 仓储端口，便于 dry-run 复用与单测。

## 1. 数据结构
```ts
// routing/domain/resolution.ts
type InboundCtx = {
  tenantId: TenantId; channelId: ChannelId; recipient: Recipient;   // recipient.schema
  message: Message;                 // 已持久化的入站（direction='inbound'）
  quotedPlatformMessageId: string | null;   // 渠道提供的“被引用消息”平台 id
  replyToId: MessageId | null;      // Web 直接给出
  principal: Principal | null;      // recipient.linkedUserId 对应成员；Web 为登录用户
  isWeb: boolean;
};
type Resolution =
  | { kind: 'command'; parsed: ParsedCommand }                       // 交给 commands
  | { kind: 'reject'; code: ErrorCode; reply: I18nKey }              // 只回提示
  | { kind: 'ask'; reply: I18nKey }                                   // 需用户选择目标（团队模式无默认）
  | { kind: 'deliver'; agent: Agent; route: Route | null; conversation: Conversation; reason: ReasonCode;
      held: boolean; device: { id: DeviceId; online: boolean } };
type ReasonCode = 'explicit_alias' | 'quote_trace' | 'focus' | 'route_default' | 'single_source' | 'supervisor' | 'web_conversation';
```

## 2. 入站路由算法
顺序固定：**指令解析 → 授权 → 溯源 → 焦点 → 模式 → held → 设备选择**（WF-ARCH §6.1）。
```ts
function routeInbound(ctx: InboundCtx, deps: Ports, opts = { dryRun: false }): Resolution {
  // ① 指令解析（DESIGN-005 §1）
  const parsed = commands.parse(ctx.message.plainText);            // NFKC；Y/N 口令；/指令；@alias
  // ② 授权
  if (!ctx.isWeb && !ctx.recipient.authorized) {
    if (parsed.kind === 'command' && parsed.name === 'bind') return { kind: 'command', parsed };
    return { kind: 'reject', code: 'RECIPIENT_UNAUTHORIZED', reply: 'im.unauthorized' };
  }
  if (deps.tenant.isEmergencyStopped(ctx.tenantId) && !(parsed.kind === 'command' && parsed.name === 'help'))
    return { kind: 'reject', code: 'EMERGENCY_STOPPED', reply: 'im.emergency_stopped' };
  if (parsed.kind === 'command' || parsed.kind === 'approval_code') return { kind: 'command', parsed };
  //   普通消息与 @alias 需要 agent.prompt
  if (!can(ctx.principal ?? recipientAsLimited(ctx.recipient), 'agent.prompt'))
    return { kind: 'reject', code: 'FORBIDDEN', reply: 'im.forbidden' };

  const routes = ctx.isWeb ? [] : deps.routes.enabledForRecipient(ctx.recipient.id);   // ix_route_targets_recipient
  const candidates = ctx.isWeb ? deps.agents.visibleTo(ctx.principal!)                    // 项目范围过滤
                               : unionSources(routes);                                    // 绑定来源并集
  let agent: Agent | null = null, route: Route | null = null, reason!: ReasonCode;

  // ③ 显式 @alias（优先于溯源：用户明确指定）
  if (parsed.kind === 'alias_message') {
    agent = deps.agents.findByAlias(ctx.tenantId, parsed.alias);
    if (!agent) return reject('NOT_FOUND', 'im.alias_not_found');
    if (!candidates.has(agent.id)) return reject('ROUTE_INVALID', 'im.alias_not_bound');
    reason = 'explicit_alias';
  }
  // ③' 溯源（G2）：引用回复只回到产生该消息的会话
  if (!agent) {
    const traced = traceReply(ctx, deps);                            // §3
    if (traced && candidates.has(traced.agentId)) { agent = deps.agents.get(traced.agentId); route = traced.route; reason = 'quote_trace'; }
  }
  // ④ 焦点（/use）
  if (!agent) {
    const focus = deps.focus.get(ctx.recipient.id);                  // recipient_focus
    if (focus && candidates.has(focus.agentId)) { agent = deps.agents.get(focus.agentId); reason = 'focus'; }
  }
  // ⑤ 模式默认
  if (!agent) {
    if (ctx.isWeb) return { kind: 'ask', reply: 'web.pick_agent' };   // Web 会话本身绑定 agent，见 §2.1
    const r = pickModeDefault(routes);                               // §4
    if (r.kind === 'ask') return r;
    ({ agent, route, reason } = r);
  }
  route ??= chooseRouteFor(agent!, routes);                          // 该 agent 在多个绑定中时：优先 mode 精确者，其次最新 version（确定性）
  if (route?.mode === 'supervisor' && reason !== 'explicit_alias') { agent = supervisorOf(route); reason = 'supervisor'; } // §4.4

  // 会话（G25：按发送人分会话）
  const conversation = deps.conversations.getOrCreateActive(agent!.id, route?.id ?? null, ctx.recipient.id, { dryRun: opts.dryRun });
  // ⑥ held（DEC-012）
  const held = deps.approvals.hasPending(agent!.id);
  // ⑦ 设备选择
  const device = selectDevice(agent!, deps);                         // §2.2
  return { kind: 'deliver', agent: agent!, route, conversation, reason, held, device };
}
```
执行（非 dry-run）：
```ts
function apply(res: Resolution, ctx) {
  switch (res.kind) {
    case 'command': return commands.execute(res.parsed, ctx);
    case 'reject': case 'ask': return replySystem(ctx, res.reply, res.code);
    case 'deliver':
      tx(() => { messages.setConversation(ctx.message.id, res.conversation.id, res.conversation.generation);  // 归属规则见 §2.3
                 audit.record('message.routed', …); });
      bus.publish('message.routed', { messageId: ctx.message.id });
      if (res.held) { heldRepo.insert(ctx.message.id, res.agent.id, pendingApprovalId); bus.publish('message.held'); return replySystem(ctx, 'im.held'); }
      gateway.sendToNode(res.device.id, 'agent.prompt', { agentId, conversationId, generation, messageId, body, from: { recipientId, userId } });
      //   sendToNode 永远先写 node_outbox；离线时只是未发出
      if (!res.device.online) replySystem(ctx, 'im.device_offline');   // DEVICE_OFFLINE（仍为 202，已排队）
      else if (caps.quoteReply || reason !== 'focus') replySystem(ctx, 'im.forwarded');  // 回执“已转给 [项目/别名]”
      twin.forward(ctx);   // 用户本人指令 → twin.capture 到其主设备（DEC-049）
  }
}
```
### 2.1 Web 渠道
- Web 消息总是发往具体会话（`POST /conversations/{id}/messages`），会话已绑定 agent：跳过 ③'④⑤，`reason='web_conversation'`；文本以 `/` 开头仍走指令；`@alias` 在 Web 会话中等价于“在该 alias 的 Web 会话里发送”（若无则新建）。
### 2.2 设备选择
```ts
function selectDevice(agent: Agent, deps): { id; online } {
  // 别名在 tenant 内唯一 → agent 唯一定位到一台设备（REQ-F-005）
  let deviceId = agent.deviceId;
  if (agent.kind === 'supervisor') deviceId = deps.devices.primaryOf(agent.ownerUserId) ?? agent.deviceId;  // 总控在主设备
  const d = deps.devices.get(deviceId);
  if (d.revokedAt) throw new AppError('DEVICE_REVOKED');
  return { id: d.id, online: deps.gateway.isOnline(d.id) };
}
```
### 2.3 入站消息与会话的归属
`messages.conversation_id` 非空（迁移约束），但入站持久化（DESIGN-002 §5.2）发生在选路之前。处理：入站先按“该接收人的最近活跃会话或其焦点会话”预归属；若选路结果不同，**不改写旧行**（append-only），而是在目标会话追加一条 `direction='inbound'` 的副本，`idempotency_key = 原 key + ':routed'`，原行保留为审计。另一选择是推迟持久化到选路之后，但会破坏“先持久化再回执”。见 §11 L-2。

## 3. 回复溯源（G2、REQ-F-017）
```ts
function traceReply(ctx, deps): { agentId; route } | null {
  const ref = ctx.replyToId
    ? deps.messages.get(ctx.replyToId)
    : ctx.quotedPlatformMessageId
      ? deps.deliveries.findByPlatformId(ctx.channelId, ctx.quotedPlatformMessageId)?.message   // 引用我方出站
        ?? deps.messages.findByPlatformId(ctx.channelId, ctx.quotedPlatformMessageId)          // 引用用户入站
      : null;
  if (!ref) return null;
  const conv = deps.conversations.get(ref.conversationId);
  if (conv.tenantId !== ctx.tenantId) return null;                // 防跨组织
  return { agentId: conv.agentId, route: conv.routeId ? deps.routes.get(conv.routeId) : null };
}
```
- 溯源到的会话若已 /clear（generation 变大），消息进入**当前 generation**（会话 id 不变），不回到旧代。
- 溯源到的智能体不在当前绑定来源中（绑定被改）→ 视为溯源失败，落到焦点并提示（DESIGN-005 §5）。

## 4. 四种模式规则
### 4.1 绑定的结构约束（创建/修改时校验，失败 `ROUTE_INVALID`，route.schema 描述）
| 模式 | sources | targets | defaultSourceId | 额外校验 |
|---|---|---|---|---|
| management 管理 | ≥1 | **=1** | 可空；sources=1 时隐含 | — |
| notification 通知 | **=1** | ≥1 | = 唯一来源 | targets 中不得包含“他人的微信 ClawBot 接收人”（DEC-046：`channel.kind='wechat_clawbot'` 且 `recipient.linkedUserId ≠ 绑定创建者` 或 `scope≠direct` → 拒绝） |
| team 团队 | ≥1 | ≥1 | 建议必填（为空时入站需 @ 或 /use） | 同上微信限制 |
| supervisor 总控 | ≥2，且恰好 1 个 `kind='supervisor'` | ≥1 | = 总控 | v1：全部来源与总控在同一设备（DESIGN-003 N-8） |
| 通用 | — | — | defaultSourceId ∈ sources | 所有 agent/recipient 同 tenant；`projectId` 与来源智能体项目相同或为其祖先（推断：项目树内可见） |

### 4.2 入站（人 → 智能体）`pickModeDefault(routes)`
```ts
function pickModeDefault(routes: Route[]) {
  // 一个接收人可能在多个绑定中；只看 enabled；按确定性顺序：supervisor > management > team > notification，同模式按 createdAt 升序
  for (const r of sortDeterministic(routes)) {
    switch (r.mode) {
      case 'supervisor':   return deliver(supervisorOf(r), r, 'supervisor');
      case 'management':   if (r.defaultSourceId) return deliver(r.defaultSourceId, r, 'route_default');
                           if (r.sources.length === 1) return deliver(r.sources[0], r, 'single_source');
                           return ask('im.pick_agent_list');          // 列出来源，提示 @别名 或 /use
      case 'team':         if (r.defaultSourceId) return deliver(r.defaultSourceId, r, 'route_default');
                           return ask('im.pick_agent_list');          // 绝不广播（DEC-006）
      case 'notification': return deliver(r.sources[0], r, 'single_source');   // 回话回到唯一来源，按发送人分会话
    }
  }
  return reject('ROUTE_INVALID', 'im.no_route');                    // 接收人没有任何绑定
}
```
### 4.3 出站（智能体 → 人）`fanoutOutbound(agentOutput)`
```ts
function fanoutOutbound(out: AgentOutputFrame, deviceId) {
  const conv = conversations.get(out.conversationId);                // 节点只能写属于自己设备的会话（校验 agent.deviceId == deviceId）
  const msg = messages.append({ direction: 'outbound', author: { kind: conv.agentKind === 'supervisor' ? 'supervisor' : 'agent', refId: conv.agentId },
                                idempotencyKey: `node:${deviceId}:${out.messageId}`, …out });
  if (out.supervisorVerdict === 'drop')  return audit('supervisor.drop');            // 只记录不投递（§4.4）
  if (out.supervisorVerdict === 'merge') return digestBuffer.add(conv, msg);         // 进入总控摘要，稍后 kind=digest 统一发
  if (orchestration.captures(conv, msg)) return;                                      // 有打开的屏障 → 只记提交，不立即发（§5）
  const recipients = targetsFor(conv, out);
  delivery.enqueue(msg.id, recipients.filter(r => priorityAllowed(out.priority, routeOf(conv).priorityFloor)));
}
function targetsFor(conv, out): Recipient[] {
  if (conv.recipientId && conv.routeId === null) return [conv.recipient];            // Web 直聊
  const route = routes.get(conv.routeId);
  switch (route.mode) {
    case 'management':   return route.targets;                                         // 唯一目标
    case 'notification': return conv.recipientId && out.replyToId && isReplyToRecipient(out, conv)
                              ? [conv.recipient]                                       // 对某接收人回话的回复只回该人（G25）
                              : route.targets;                                         // 主动通知 → 全部目标
    case 'team':         return conv.recipientId && out.replyToId ? [conv.recipient] : route.targets;
    case 'supervisor':   return out.supervisorVerdict === 'reply' ? [originator(conv, out)] : route.targets;  // escalate → 全部目标
  }
}
```
- `priorityFloor`：只投递优先级不低于下限的消息（p0 最高）；被过滤的不生成 delivery（审计记 `suppressed_by_floor`）。
- 每个 (message, recipient) 再经 `permissions-filter.filterOutbound`（allow/mask/drop），结果写 `deliveries.filters_applied`（REQ-F-027/028）。

### 4.4 总控模式（DEC-018、REQ-F-022/023）
| 环节 | 规则 |
|---|---|
| 入站 | 未显式 @ 的消息一律给总控；`/boss` 显式给总控的“随时对话”会话（独立 conversation：`route_id` 相同、`recipient_id` 相同，但 agent=总控；与执行任务的工人会话分开，不进入工人队列） |
| 工人输出 | 节点 supervisor 先判 verdict（reply/merge/escalate/drop + 理由，存 node `supervisor_verdicts`），再回传 `agent.output.supervisorVerdict` |
| 中转执行 | reply → 只回发起人；merge → 进摘要缓冲；escalate → 全部目标（`priority ≥ p1`，必要时以 `approval.kind='supervisor_escalation'` 形式）；drop → 不投递仅审计 |
| 缺 verdict | supervisor 绑定下工人输出 `supervisorVerdict=null` → 视为违反 DEC-018：不投递，记 `error` 审计并 p1 通知设备所有者（推断：防节点旧版本绕过） |
| 降级 | 预算超限时节点改用规则把关（`by_rules=1`），中转无感知（DESIGN-022） |

## 5. 汇总屏障（G1、REQ-F-021）
### 5.1 状态机（barrier.schema `status`）
```text
            POST /barriers（expectedSources≥2, timeoutSec 10..86400）
                    │
                    ▼
                 [open] ──提交（来源 ∈ expected 且首次）──▶ [open]（received+1）
                  │  │
     received == expected                 now ≥ openedAt + timeoutSec
                  │  │                                  │
                  ▼  └──────────────────────────────────▼
             [complete]                            [timed_out]
                  │           用户取消（无端点，见 §11 L-4）→ [cancelled]
                  ▼
        生成并投递一条汇总消息（summary_message_id）→ barrier.closed
```
### 5.2 提交判定
```ts
function captures(conv, msg): boolean {
  const b = barriers.openForRoute(conv.routeId);                    // 每个 route 同时至多一个 open 屏障（设计约束）
  if (!b || !b.expectedSources.includes(conv.agentId)) return false;
  if (!['final', 'digest'].includes(msg.kind)) return false;        // status/error 不算提交
  tx(() => { insertOrIgnore(barrier_submissions, { barrierId: b.id, agentId: conv.agentId, messageId: msg.id });
             if (count(b) === b.expectedSources.length) close(b, 'complete'); });
  return true;                                                       // 被屏障吸收，不单独投递
}
```
- 节点显式 `barrier.submit{barrierId, agentId, messageId}` 帧同样调用提交（幂等，PK 去重）；中转自动关联是主路径，因为节点不知道 barrierId（§11 L-3）。
- 一个来源多次输出：只取**首次**提交（PK 冲突忽略）；屏障 open 期间该来源的后续 `final` 不单独投递，只记审计（防止汇总前后重复单发）。设计选择，可推翻。
### 5.3 汇总消息
```text
blocks:
  heading(1, "{route.name} 汇总 · {openedAt 本地时间}")
  对每个已提交来源（按 expectedSources 顺序）：heading(2, "[{项目}/{alias}]") + 该提交消息的 blocks
  若 timed_out：callout(warn, "以下来源未在 {timeoutSec} 秒内提交：{alias1}、{alias2}")
fields: 合并各提交消息的 fields（同名字段以来源别名为前缀：`{alias}.{field}`），供过滤与脱敏（G3）
```
投递：作为 `author.kind='system'` 的出站消息，经 4.3 的 `targetsFor`（mode 的全部目标）+ 过滤 → 每个接收人看到各自可见字段（REQ-F-027 场景 2）。

## 6. held 释放
```ts
on approval.decided(approval):
  const items = held.pendingForAgent(approval.agentId).orderBy('held_at');   // 释放该智能体的全部暂存（不仅本审批）
  for (const h of items) {
    if (approvals.hasPending(approval.agentId)) break;                       // 若又出现新审批，剩余继续暂存
    held.markReleased(h.messageId);
    gateway.sendToNode(deviceOf(agent), 'agent.prompt', promptFrom(h.messageId));   // 按序；节点侧再按会话串行
  }
```

## 7. 按发送人分会话（G25、REQ-F-017）
- 会话键 = `(agentId, routeId, recipientId)`；`ux_conversations_active` 保证每键至多一个 active。
- 通知模式：一个来源 → N 个接收人；接收人 A、B 的回话分别落入 `(src, route, A)` 与 `(src, route, B)` 两个会话 → 节点上是两个 ACP 会话（两个子进程或按需回收），上下文互不串（REQ-F-017 验收）。
- 主动通知（来源首发）记在哪个会话？来源的主动输出不属于某个接收人：记入 `(src, route, recipient=NULL)` 的“广播会话”，各接收人的回话会话首条消息 `reply_to_id` 指向广播消息（溯源可用）。
- 团队模式同理；管理模式只有一个接收人，天然一个会话。
- get-or-create 并发：`INSERT … ON CONFLICT DO NOTHING` 后再 `SELECT`（唯一索引兜底），单写者下无竞态。

## 8. dry-run（REQ-F-016、`POST /routes/dry-run`）
```ts
function dryRun(req: { recipientId; text; replyToMessageId? }, principal) {
  assertPermission(principal, 'route.dry_run');
  const ctx = syntheticInbound(req, principal);                      // 不落库；platformMessageId 为空
  const res = routeInbound(ctx, readOnlyPorts, { dryRun: true });    // getOrCreateActive 只查不建
  const preview = [];
  if (res.kind === 'deliver') {
    const sample = { blocks: [{ type: 'paragraph', text: req.text }], fields: {} };   // 以输入文本作为“该智能体的回复样例”
    for (const r of targetsFor(previewConversation(res), { kind: 'final', priority: 'p2' })) {
      const f = permissionsFilter.filterOutbound(sample, r, res.route);
      preview.push({ recipientId: r.id, channelKind: r.channel.kind, dropped: f.dropped, filtersApplied: f.applied,
                     renderedAs: render(f.body, caps(r.channel)).renderedAs, text: render(...).text });
    }
  }
  return { targetAgentId: res.kind === 'deliver' ? res.agent.id : null,
           reason: explain(res),            // 例："焦点：z1（/use 设置）"、"团队模式无默认来源，需要 @别名"
           held: res.kind === 'deliver' && res.held,
           outboundPreview: preview };      // 契约中 items 为 object，字段为本文约定（§11 L-5）
}
```
- dry-run 不产生任何写入、不发帧、不审计（只读仓储端口在类型上禁止写）。

## 9. 确定性与测试
- 同一输入（绑定表快照 + 焦点 + 待审批 + 设备在线）必得同一结果；排序键全部显式（createdAt、id）。
- 单测矩阵（TASK-044/102）：模式 4 × {有/无 @alias} × {有/无引用} × {有/无焦点} × {有/无默认来源} × {held 是/否} × {设备在线/离线}，期望结果以表格夹具维护；dry-run 与真实路由共享同一测试表。

## 10. /clear、/stop 的逻辑要点
- `/clear [alias]`：目标解析同 §2 的 ③④⑤（不含溯源）；`UPDATE conversations SET generation=generation+1` → 发 `agent.clear{newGeneration}`；held 中属于旧代的消息随之进入新代（不丢）。
- `/stop all`：tenant 急停（DESIGN-005 §2）；delivery 工作者跳过该 tenant；路由第 ② 步拒绝。

## 11. 与契约的差异 / 待办
| # | 发现 | 处理 |
|---|---|---|
| L-1 | 契约未定义一个接收人同时属于多个绑定时的优先顺序 | 本文 §4.2 确定性顺序（supervisor > management > team > notification，createdAt 升序） |
| L-2 | `messages.conversation_id` 必填，但入站持久化先于选路 | §2.3 预归属 + 追加副本；若认为副本不妥，需契约/迁移允许入站先存“待路由收件箱” |
| L-3 | 屏障与智能体输出的关联：节点不知道 barrierId，`barrier.submit` 帧难以由节点主动发出 | 中转自动关联为主路径；建议契约在 `agent.prompt` 增加可选 `barrierId` 以支持显式提交 |
| L-4 | 无取消屏障端点；status 有 `cancelled` | v1 不提供取消；路由删除时级联置 cancelled |
| L-5 | dry-run `outboundPreview.items` 为未定义结构的 object | 本文 §8 约定字段；建议契约细化 |
| L-6 | 总控输出的 `reply` 需要知道“发起人”，`agent.output` 无发起人字段 | 以 `replyToId` 指向的入站消息作者为发起人；无 replyToId 时按 escalate 处理 |
| L-7 | 主动通知的“广播会话”`recipient_id=NULL` 与 Web 直聊会话同形（route 非空可区分） | 以 `route_id IS NOT NULL AND recipient_id IS NULL` 识别广播会话；建议契约 conversation 增 `kind` 字段 |
