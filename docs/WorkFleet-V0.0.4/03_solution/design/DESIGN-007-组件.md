---
id: DESIGN-007
type: design
title: 组件与端口详细设计（ChannelAdapter、InputAdapter/AcpDialect、Renderer、Repository、事件总线）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - "DEC-007"
  - "DEC-008"
  - "DEC-024"
  - "ADR-002"
  - "ADR-005"
  - "ADR-007"
  - "ADR-013"
  - "REQ-NF-008"
  - "REQ-NF-009"
  - "packages/contracts/adapters/{channel-capabilities.schema.json,channel-kinds.v1.json,input-adapter-spec.schema.json,input-adapters.v1.json}"
  - "packages/contracts/schemas/entities/**"
  - "packages/contracts/protocol/**"
  - "packages/contracts/events/domain-events.json"
  - "packages/contracts/errors/error-codes.json"
  - "V0.0.2/10-参考项目/12（Paperclip ServerAdapterModule、能力矩阵）"
  - "V0.0.2/10-参考项目/14（Orca AcpLaunchSpec、AcpDialect、peer）"
---

# DESIGN-007 组件与端口

## 1. 通则
- 端口（接口）定义在**使用方模块的 `domain/ports.ts`**，实现放 `infrastructure/`（PROJECT-STRUCTURE-SPEC §3.1）。跨模块使用的端口经提供方 `index.ts` 导出类型。
- 所有数据类型从 `@workfleet/contracts/generated` 导入（ADR-002），下文以 `C.<Name>` 表示，例如 `C.ChannelCapabilities`（channel-capabilities.schema.json）、`C.MessageBody`（message-body.schema.json）。本文新增的类型只用于进程内，不跨进程。
- 错误：端口实现只抛 `AppError(code)` 或下文定义的渠道错误子类；code 必须在 `errors/error-codes.json` 中（启动自检）。
- 进程内加载，接口按“可迁出进程”设计：方法参数/返回值全部可 JSON 序列化（除 `AbortSignal`、回调），为 DESIGN-009 §6 插件进程外化留路（DEC-008）。

## 2. ChannelAdapter（中转 `channels` 模块）
```ts
// apps/relay/src/modules/channels/domain/ports.ts
import type * as C from '@workfleet/contracts/generated';

/** 每种渠道一个工厂；注册表按 kind 查找。新增渠道 = 新目录 + registry.register(factory)（REQ-NF-008）。 */
export interface ChannelAdapterFactory {
  readonly kind: string;                              // 'wechat_clawbot' | 'feishu' | … （不做枚举，DEC-008）
  readonly displayName: string;
  readonly configSchema: JsonSchema;                  // 控制台表单（DEC-010）；不含密钥
  readonly credentialSchema: JsonSchema;              // 凭据表单（经 POST /channels/{id}/credential）
  readonly defaultCapabilities: C.ChannelCapabilities; // 契约 channel-kinds.v1 为初值，缺省字段由工厂补全
  readonly supportsQrLogin: boolean;
  create(ctx: ChannelContext): ChannelAdapter;
}

export interface ChannelContext {
  readonly channelId: C.ChannelId;
  readonly tenantId: C.TenantId;
  readonly config: Record<string, unknown>;           // channels.config（已过 configSchema 校验）
  readonly credentials: CredentialVault;              // 解密后的凭据读写（channels.credential_enc）
  readonly cursor: CursorStore;                       // channels.cursor（长轮询游标）
  readonly tokens: ChannelTokenStore;                 // channel_tokens（如微信 context_token + 额度计数）
  readonly http: HttpClient;                          // 带超时/代理/trace 的 fetch 封装
  readonly log: Logger;
  readonly clock: Clock;
  emitInbound(evt: InboundEvent): Promise<InboundAck>;   // 交给 channels.application.onInbound（先持久化）
  emitHealth(h: HealthSignal): void;                      // 交给健康状态机（DESIGN-002 §7.4）
}

export interface ChannelAdapter {
  /** 实测能力（可覆盖 defaultCapabilities，例如飞书租户版本差异）；核心只按能力降级，不写渠道特判。 */
  capabilities(): C.ChannelCapabilities;
  /** 开始收消息（长连接/长轮询/stream）；signal 中止即退出循环。返回前不得阻塞超过 10 s。 */
  start(signal: AbortSignal): Promise<void>;
  stop(): Promise<void>;
  /** 发送一条已渲染内容；必须幂等：同 idempotencyKey 重试不得产生两条（平台不支持时尽力而为，并在 capabilities 注明）。 */
  send(req: OutboundRequest): Promise<SendResult>;
  /** capabilities.editMessage=true 时必须实现。 */
  edit?(req: EditRequest): Promise<SendResult>;
  /** 平台要求的入站回执/“正在输入”（≤3 s，REQ-NF-001）。 */
  acknowledge?(evt: InboundEvent): Promise<void>;
  /** 按钮回调需要应答时（如卡片交互）。 */
  answerAction?(actionId: string, toast?: string): Promise<void>;
  beginQrLogin?(): Promise<{ loginId: string; qrImageDataUrl: string; expiresAt: string }>;   // 契约 qr-login 响应
  pollQrLogin?(loginId: string): Promise<{ state: 'waiting'|'scanned'|'confirmed'|'expired'|'failed'; errorCode?: string }>;
  /** 用于 bot_identity_hash（DEC-034）：返回平台上稳定的 Bot 身份（app_id、bot user id 等），中转做 sha256。 */
  identity(): Promise<{ platformBotId: string }>;
  health(): HealthSnapshot;
  /** 测试消息（POST /channels/{id}/test）。 */
  test?(recipientPlatformId: string): Promise<SendResult>;
}

export interface InboundEvent {
  platformMessageId: string;                          // 幂等键组成部分（channelId+platformMessageId，domain-events message.received）
  platformChatId: string;  scope: 'direct'|'group'|'channel';
  senderPlatformId: string; senderDisplayName: string;
  text: string;                                       // 已转纯文本；富文本保留在 raw
  quotedPlatformMessageId: string | null;             // 引用回复（DESIGN-006 §3）
  mentionsBot: boolean;
  action?: { actionId: string; payload: { approvalId: string; optionId: string } };   // 按钮回调（审批）
  attachments: Array<{ platformFileId: string; name: string; mime: string; sizeBytes: number }>;  // 由中转下载转存（resources.json imFetch）
  receivedAt: string; raw?: unknown;                  // raw 不入库，只在 debug 日志
  sessionToken?: string;                              // 如微信 context_token；由 onInbound 写入 tokens
}
export interface OutboundRequest {
  idempotencyKey: string;                             // = deliveryId（+attempt 不变）
  recipient: { platformId: string; scope: 'direct'|'group'|'channel' };
  payload: RenderedPayload;                           // §4
  replyToPlatformMessageId?: string;                  // quoteReply=true 时用于线程化
  priority: 'p0'|'p1'|'p2'|'p3';
}
export interface EditRequest extends OutboundRequest { platformMessageId: string }
export interface SendResult { platformMessageId: string | null; sentAt: string }

/** 适配器只能抛以下错误，DeliveryWorker 据此决定重试（DESIGN-002 §7.1）。 */
export class TransientError extends Error {}
export class RateLimitedError extends Error { constructor(public retryAfterSec: number) { super() } }
export class CredentialExpiredError extends Error {}      // → CHANNEL_CREDENTIAL_EXPIRED
export class QuotaExhaustedError extends Error {}         // → CHANNEL_QUOTA_EXHAUSTED
export class PermanentError extends Error { constructor(public code: 'CHANNEL_CAPABILITY_UNSUPPORTED'|'PAYLOAD_TOO_LARGE'|'VALIDATION_FAILED') { super() } }

export type HealthSignal = { kind: 'connected' } | { kind: 'disconnected'; reason: string } | { kind: 'credential_expired' } | { kind: 'consumer_conflict' } | { kind: 'send_failed'; error: string };
export interface HealthSnapshot { state: C.Channel['health']; lastInboundAt: string | null; lastOutboundAt: string | null; detail?: string }

export interface CredentialVault { get<T>(): Promise<T | null>; put<T>(v: T): Promise<void>; clear(): Promise<void> }
export interface CursorStore { get(): Promise<string | null>; set(v: string): Promise<void> }
export interface ChannelTokenStore {
  get(recipientPlatformId: string): Promise<{ token: string; refreshedAt: number; sentSinceRefresh: number } | null>;
  refresh(recipientPlatformId: string, token: string): Promise<void>;   // 入站时：sent_since_refresh=0
  incrementSent(recipientPlatformId: string): Promise<number>;
}
```
- 适配器目录约定（DESIGN-002 §3）：`index.ts`（导出 Factory）、`client.ts`（平台 HTTP/WS）、`inbound.ts`（平台事件 → InboundEvent）、`render.ts`（RenderedPayload → 平台消息体）、`capabilities.ts`。
- 渠道一致性测试（TASK-126）：同一套用例对每个 Factory 运行（FakeChannel 方言 + 录制）：幂等发送、长文本截断、按钮回调映射、凭据失效抛 CredentialExpiredError、stop 后无回调。

## 3. 输入端：InputAdapter / AgentSession / AcpDialect（节点 `agents` 模块）
```ts
// apps/node/src/modules/agents/domain/ports.ts
import type * as C from '@workfleet/contracts/generated';

/** 一个 family 一个实现：acp（通用，表驱动）、coze_http、webhook。新增 ACP 智能体 = spec 一行 + 夹具（DEC-007、REQ-NF-008）。 */
export interface InputAdapter {
  readonly family: C.InputAdapterSpec['family'];
  detect(spec: C.InputAdapterSpec): Promise<DetectResult>;          // 本机是否安装、版本是否 ≥ minVersion
  openSession(req: OpenSessionRequest): Promise<AgentSession>;
}
export interface DetectResult { installed: boolean; version: string | null; path: string | null; meetsMinVersion: boolean; hint?: string }
export interface OpenSessionRequest {
  spec: C.InputAdapterSpec;
  agent: C.Agent;                                     // workdir、writeMode、config
  cwd: string;                                        // workdir 或 worktree（workspace-guard 决定）
  nativeSessionId: string | null;                     // 有值且 spec.supportsLoadSession → session/load
  mcpServers: McpServerRef[];
  env: Record<string, string>;
  signal: AbortSignal;
}
export interface AgentSession {
  readonly nativeSessionId: string | null;
  prompt(input: C.MessageBody, ctx: TurnContext): Promise<TurnResult>;
  cancel(): Promise<void>;                            // ACP session/cancel
  close(): Promise<void>;                             // 结束并终止进程树（DESIGN-003 §6.2）
  readonly exited: Promise<{ code: number | null; signal: string | null }>;
}
export interface TurnContext {
  signal: AbortSignal;
  onUpdate(u: AgentUpdate): void;                     // 写转录 + 聚合（DESIGN-003 §4.1）
  onPermission(req: PermissionRequest): Promise<PermissionOutcome>;   // → approval.request，等待 approval.decision
  onUsage?(u: { inputTokens: number; outputTokens: number }): void;   // Coze 等可报告用量
}
export type AgentUpdate =
  | { kind: 'text'; role: 'agent'|'thought'; text: string }
  | { kind: 'tool_call'; id: string; title: string; status: 'pending'|'in_progress'|'completed'|'failed'; detail?: string }
  | { kind: 'plan'; entries: Array<{ text: string; status: string }> }
  | { kind: 'other'; method: string; raw: unknown };
export interface PermissionRequest { toolCallTitle: string; toolCallRaw: unknown; options: Array<{ optionId: string; label: string; kind: 'allow_once'|'allow_always'|'reject'|'custom' }> }
export type PermissionOutcome = { selected: string } | { cancelled: true };
export interface TurnResult { stopReason: 'end_turn'|'max_tokens'|'refusal'|'cancelled'|'error'; finalText: string; error?: { code: string; message: string } }

/** 方言钩子：吸收各家 ACP 偏差（借鉴 Orca AcpDialect；spec.dialect 为 id，空 = 标准 ACP）。 */
export interface AcpDialect {
  readonly id: string;
  /** initialize/session.new 参数改写（例如需要 clientCapabilities.fs、额外 _meta）。 */
  patchInitialize?(params: AcpInitializeParams): AcpInitializeParams;
  patchNewSession?(params: AcpNewSessionParams): AcpNewSessionParams;
  /** 认领智能体发来的非标准请求（如 cursor/ask_question，V0.0.2/08 提及），返回 null 表示不认领 → 回 JSON-RPC MethodNotFound。 */
  claimRequest?(method: string, params: unknown): DialectClaim | null;
  /** 非标准通知 → AgentUpdate。 */
  mapNotification?(method: string, params: unknown): AgentUpdate | null;
  /** 权限请求摘要与风险（覆盖默认 classify，DESIGN-003 §4.2）。 */
  summarizePermission?(req: PermissionRequest): { summary: string; risk: 'low'|'medium'|'high' };
}
export type DialectClaim =
  | { kind: 'ask_user'; question: string; options?: string[]; respond(answer: string): unknown }   // 以 approval(kind=major_decision) 呈现
  | { kind: 'auto'; result: unknown };
```
- `AcpPeer`（`infrastructure/acp/peer.ts`，内部类，不作为端口）：NDJSON 读写、请求 id 分配、超时、单行 16 MiB、写队列 32 MiB、并发 128（Orca 上限语义，V0.0.2/14 已确认；实现为 clean 自写或按 DESIGN-008 移植并保留版权）。
- ACP 协议类型：优先由官方 TS SDK 提供（包名/版本证据不足，ADR-007、U-05，TASK-021 确认）；若不可用则从官方 JSON Schema 生成到 `infrastructure/acp/types.ts`。

## 4. Renderer（IR → 渠道）
```ts
// apps/relay/src/modules/delivery/domain/render.ts（纯函数，可单测）
export interface RenderOptions { priority: 'p0'|'p1'|'p2'|'p3'; tags: string[]; quota?: { remaining: number }; locale: 'zh-CN'|'en-US' }
export interface RenderedPayload {
  renderedAs: C.Delivery['renderedAs'];               // 'card' | 'markdown' | 'text' | 'digest'（delivery.schema）
  text: string;                                       // 必有：任何渠道的最终降级文本（≤ maxMessageChars）
  markdown?: string;                                  // capabilities.markdown
  card?: CardIR;                                      // capabilities.cards：渠道无关卡片结构（标题、分节、按钮、kv）
  buttons?: Array<{ label: string; actionPayload: { approvalId: string; optionId: string } }>;   // capabilities.buttons
  truncated: boolean;
  parts?: RenderedPayload[];                          // 超长拆分（maxMessageChars），按序发送
}
export function render(body: C.MessageBody, caps: C.ChannelCapabilities, opts: RenderOptions, lookups: { approval(id): C.Approval }): RenderedPayload;

/** 每个渠道的 render.ts 只把 RenderedPayload 转成平台体，不做降级决策。 */
export interface PlatformRenderer<TPlatformBody> { toPlatform(p: RenderedPayload): TPlatformBody | TPlatformBody[] }
```
降级矩阵（IR 块 × 能力，DEC-024）：
| IR 块 | cards | markdown | 纯文本 |
|---|---|---|---|
| heading | 卡片标题/分节标题 | `#`/`##` | `【文本】` |
| paragraph | 文本元素 | 原样 | 原样 |
| list | 列表元素 | `- ` / `1. ` | `• ` / `1. ` |
| code | 代码元素 | ``` 围栏 | 前缀 4 空格；>40 行截断并提示 `/history` |
| table | 表格元素（不支持则转 kv） | markdown 表格 | `列1：值；列2：值` 每行一条 |
| callout | 带色块 | `> ⚠ ` | `⚠ ` 前缀 |
| kpi | kv 字段 | `**label**：value（delta）` | `label：value（delta）` |
| attachment | 文件消息（attachments=true） | 链接（签名 URL 5 分钟，resources.json） | “附件：name（请在控制台下载）” |
| approval | 卡片 + 按钮 | 文本 + 按钮（buttons=true） | 文本 + “回复 Y{n}/N{n}”（DESIGN-005 §3） |
| status_card | editMessage=true 时编辑同一张卡 | 同左 | 不发（只发 final），除非超过 10 分钟发一次“进行中” |
- 规则：先按 `maxMessageChars` 计算，超长先截断代码块与表格，再拆分 `parts`；微信等 `proactiveQuota` 渠道拆分会消耗额度 → 改为截断 + “完整内容在控制台”（DEC-023）。
- `tags` 前缀 `[项目/别名]`（message-body.tags）在所有形态中位于首行。

## 5. Repository 端口（两侧通用约定）
```ts
// shared/domain/repository.ts
export interface UnitOfWork { run<T>(fn: (tx: Tx) => T): T }        // better-sqlite3 同步事务；BEGIN IMMEDIATE
export interface Page<T> { items: T[]; nextCursor: string | null; hasMore: boolean }   // page.schema.json
export interface PageRequest { cursor?: string; limit?: number }                       // page-request.schema.json（limit ≤200）
```
中转关键端口（定义在使用方 domain/ports.ts）：
```ts
export interface ConversationRepo {
  get(id: C.ConversationId, tx?: Tx): C.Conversation | null;
  getByDisplayId(tenantId, displayId): C.Conversation | null;
  getByNativeSessionId(tenantId, nativeId): C.Conversation | null;
  findActive(agentId, routeId | null, recipientId | null): C.Conversation | null;
  getOrCreateActive(input: { tenantId; projectId; agentId; routeId; recipientId }, tx): C.Conversation;   // ux_conversations_active 兜底
  bumpGeneration(id, tx): number;
  list(filter: { tenantId; projectId?; agentId?; scope: ProjectScope }, page: PageRequest): Page<C.Conversation>;
}
export interface MessageRepo {
  append(m: NewMessage, tx): { message: C.Message; duplicate: boolean };   // INSERT … ON CONFLICT(idempotency_key) DO NOTHING
  get(id): C.Message | null;
  findByPlatformId(channelId, platformMessageId): C.Message | null;
  page(conversationId, generation: number | null, page: PageRequest): Page<C.Message>;
}
export interface DeliveryRepo {
  enqueueMany(rows: NewDelivery[], tx): number;                         // ux_deliveries 去重；每事务 ≤50
  claimDue(now: number, limit: number, tx): DeliveryRow[];              // 置 sending
  markSent(id, platformMessageId, tx): void; markFailed(id, error, nextAttemptAt, tx): void; markDead(id, error, tx): void; suppress(id, reason, tx): void;
  findByPlatformId(channelId, platformMessageId): DeliveryRow | null;   // 需索引（DESIGN-004 D-2）
}
export interface ApprovalRepo {
  insert(a: C.Approval, tx): C.Approval;                                 // 内部分配 shortCode
  getPendingByShortCode(tenantId, shortCode): C.Approval | null;
  hasPendingForAgent(agentId): boolean;
  decide(id, decidedBy, optionId, status, tx): C.Approval;               // 只在 pending 时生效，否则抛 APPROVAL_ALREADY_DECIDED
  dueForExpiry(now, limit): C.Approval[];
}
export interface RouteRepo { enabledForRecipient(recipientId): C.Route[]; routesForAgent(agentId): C.Route[]; get(id): C.Route; save(r, expectedVersion, tx): C.Route }
export interface AuditRepo { append(e: C.AuditEntry, tx?): void; query(filter, page): Page<C.AuditEntry> }
```
节点关键端口：`SessionRepo`、`PromptQueueRepo{enqueue, nextFor(conversationId), mark(state)}`、`LeaseRepo{tryAcquireExclusive, insertWorktree, heartbeat, release}`、`RelayOutboxRepo`、`TwinRepo`、`ModelProfileRepo`、`UsageRepo{sumSince(profileId, since)}`。
- 实现约束：仓储只在 `infrastructure/`，用 Kysely；返回契约类型（mapper 负责 snake_case ↔ camelCase、INTEGER ms ↔ RFC 3339）。

## 6. 事件总线（进程内，契约 domain-events.json）
```ts
// shared/application/event-bus.ts
export type EventName = C.DomainEventName;          // 由 domain-events.json 生成的联合类型（18 个）
export interface DomainEvent<N extends EventName = EventName> { name: N; idempotencyKey: string; tenantId?: string; traceId: string; at: string; payload: EventPayload<N> }
export interface EventBus {
  publish<N extends EventName>(e: DomainEvent<N>): void;                // 仅在事务 COMMIT 后调用
  subscribe<N extends EventName>(name: N, handlerId: string, h: (e: DomainEvent<N>) => Promise<void>): Unsubscribe;
}
```
- 语义：同步入队、异步执行（`queueMicrotask` 批处理）；每个处理器独立 try/catch，失败记日志与 `event_handler_failures_total` 指标，不影响其他处理器。
- 幂等：处理器以 `(handlerId, idempotencyKey)` 去重（进程内 LRU 10 000 条；持久副作用依赖表约束兜底）。
- 不保证跨重启送达：凡必须发生的副作用都由“表即队列”保证（DESIGN-002 §9）。
- 订阅清单（主要）：`message.received`→routing；`message.routed`/`delivery.sent`/`delivery.failed`/`route.updated`/`approval.decided`/`emergency.stopped`→audit；`channel.health_changed`→notifications；`approval.requested`→notifications（p0）+ Web stream；`device.online`→node-gateway 续传 + held 检查；`barrier.closed`→delivery。

## 7. 跨进程端口
```ts
// 中转 node-gateway/index.ts
export interface NodeGateway {
  sendToNode<T extends C.FrameType>(deviceId: C.DeviceId, type: T, payload: C.FramePayload<T>, opts?: { idempotencyKey?: string; traceId?: string }): { seq: number };   // 先写 node_outbox
  onNodeFrame<T extends C.FrameType>(type: T, h: (deviceId: C.DeviceId, payload: C.FramePayload<T>, env: C.Envelope) => Promise<void>): void;
  request<T>(deviceId, type: 'history.query', payload, timeoutMs: number): Promise<C.FramePayload<'history.result'>>;   // requestId 关联
  isOnline(deviceId): boolean;
}
// 节点 relay-link/index.ts
export interface RelayLinkPort {
  send<T extends C.FrameType>(linkId: C.RelayLinkId, type: T, payload: C.FramePayload<T>): { seq: number };   // 先写 relay_outbox
  on<T extends C.FrameType>(type: T, h: (linkId, payload, env) => Promise<void>): void;
  status(linkId): C.RelayLink['status'];
}
```
## 8. 其他端口
| 端口 | 方法 | 实现 |
|---|---|---|
| `Clock` | `now(): number` | 系统时钟；测试用可控时钟 |
| `IdGen` | `next(prefix): string` | 前缀+ULID（ADR-012） |
| `Keychain`（节点） | `get(ref)`、`set(ref, secret)`、`delete(ref)`、`backend(): 'dpapi'|'keychain'|'libsecret'|'file'` | DESIGN-003 §3 core/security/keychain |
| `ModelProvider`（节点） | `chat(req: {messages, tools?, stream?, params}, signal): AsyncIterable<Chunk> & Promise<{usage}>` | openai_compatible、anthropic 薄客户端（ADR-013） |
| `PushSender`（中转） | `send(sub, payload): Promise<'ok'|'gone'|'error'>` | VAPID |
| `Masker`（中转） | `mask(value, style: 'full'|'partial'|'hash'): string` | permissions-filter |

## 9. 契约引用表
| 端口/类型 | 契约文件 |
|---|---|
| ChannelAdapter.capabilities | adapters/channel-capabilities.schema.json、channel-kinds.v1.json |
| ChannelAdapterFactory.kind | adapters/channel-kinds.v1.json（kind 字符串，不枚举） |
| beginQrLogin/pollQrLogin | api/relay.openapi.json `/channels/{id}/qr-login*` |
| InputAdapter / spec | adapters/input-adapter-spec.schema.json、input-adapters.v1.json |
| Renderer 输入 / renderedAs | schemas/entities/message-body.schema.json、delivery.schema.json |
| Repository 返回类型 | schemas/entities/*.schema.json、schemas/common/page*.schema.json |
| EventBus 事件名/幂等键 | events/domain-events.json |
| NodeGateway / RelayLinkPort | protocol/envelope.schema.json、protocol/frames/*.schema.json |
| 错误类 → 错误码 | errors/error-codes.json |

## 10. 与契约的差异 / 待办
| # | 发现 | 处理 |
|---|---|---|
| P-1 | `channel-kinds.v1.json` 各条只给部分能力字段（缺 threads、quoteReply、groupChat、rateLimitPerSec、maxMessageChars、attachments 等 schema 必填项） | 工厂 `defaultCapabilities` 补全缺省（保守取 false/0），各渠道 TASK 实测后由 Agent-Contract 更新清单 |
| P-2 | 契约 qr-login 状态无 errorCode | `pollQrLogin` 进程内返回 errorCode，HTTP 层暂不透出（DESIGN-005 I-6） |
| P-3 | `domain-events.json` 只有名称/触发/幂等键，无 payload schema | 事件 payload 类型在 `shared/domain/events.ts` 手写并标注“进程内”；建议契约补 payload |
| P-4 | 权限选项 kind：ACP 原生选项种类与契约 `allow_once/allow_always/reject/custom` 的映射未定义（ACP 侧可能区分 reject_once/reject_always） | 映射：reject_* → `reject`；未知 → `custom`；TASK-021 以官方类型校对 |
| P-5 | `DialectClaim.ask_user` 以审批呈现，但 approval.options 需 ≥2 个且 label ≤40 字；自由文本回答无载体 | v1 只支持有限选项的问题；自由文本问题以普通消息呈现，用户回复经溯源回到会话（不作为 ACP 响应）——实际能否满足各方言待实测 |
