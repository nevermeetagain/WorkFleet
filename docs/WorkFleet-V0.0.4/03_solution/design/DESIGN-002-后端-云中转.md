---
id: DESIGN-002
type: design
title: 后端详细设计 · 云中转（apps/relay）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - "WF-ARCH §3/§4.1/§5/§6/§7"
  - "ADR-001"
  - "ADR-003"
  - "ADR-005"
  - "ADR-006"
  - "ADR-009"
  - "ADR-011"
  - "ADR-012"
  - "DEC-004"
  - "DEC-005"
  - "DEC-008"
  - "DEC-012"
  - "DEC-013"
  - "DEC-017"
  - "DEC-023"
  - "DEC-024"
  - "DEC-030"
  - "DEC-034"
  - "DEC-037"
  - "DEC-051"
  - "REQ-F-002/003/009/016/017/020/021/028/030/033"
  - "REQ-NF-001/003/004/007"
  - "packages/contracts/**"
  - "database/migrations/relay/0001_init.sql"
  - "PROJECT-STRUCTURE-SPEC §8/§9"
  - "ownership-matrix.md（Agent-Relay/Agent-Channel 路径）"
---

# DESIGN-002 后端 · 云中转

## 1. 范围
云中转 = 单进程 Node 22 服务（Fastify 5 + ws + better-sqlite3 + Kysely + pino + ajv，ADR-009），systemd 管理，监听 `127.0.0.1:5101`，由 Caddy/Nginx 在 443 终止 TLS 后反代（WF-ARCH §3、DEC-051）。它持有：账号与组织、设备与节点通道、IM 渠道连接、路由、消息账本、投递、审批、汇总屏障、过滤、审计、通知、Web 控制台静态资源。**不运行模型、不存模型 Key**（REQ-C-006）。

## 2. 进程与启动
```text
bootstrap/main.ts
  1 loadConfig()                       # DESIGN-011：env > relay.yaml > 默认；校验失败即退出码 78
  2 acquireInstanceLock(dataDir)       # <dataDir>/relay.lock，O_EXCL + pid/hostname；陈旧锁回收规则同 DESIGN-003 §8（DEC-003）
  3 openDatabase()                     # 写连接 1 个 + 读连接 N 个（DESIGN-010 §4）；PRAGMA；运行迁移（DESIGN-004 §5）
  4 loadMasterKey()                    # WF_MASTER_KEY_FILE（0600）；缺失则拒绝启动（凭据加密依赖，DEC-004）
  5 container = buildContainer()       # 手写组合根：仓储实现 → 应用服务 → 接口；无 DI 框架
  6 app = buildFastify(container)      # 中间件顺序 §6；注册各模块 interfaces/http
  7 gateway.attach(app.server)         # /api/v1/node-gateway 与 /api/v1/stream 两个 ws 升级端点
  8 channels.startAll()                # 对 health != disabled 的渠道 start()（DESIGN-007 §2）
  9 workers.startAll()                 # §7 全部后台工作者
 10 app.listen({host, port})           # 默认 127.0.0.1:5101
  SIGTERM → 停止接收新请求 → workers.stop()（等待在途 ≤10 s）→ channels.stopAll() → gateway 关闭（发送 close 1001）→ wal_checkpoint(TRUNCATE) → 释放锁 → exit 0
```

## 3. 目录树（文件级）
> 分层：`interfaces → application → domain ← infrastructure`（WF-ARCH §5）。每个模块只经 `index.ts` 暴露公开 API。下表列出的文件即实现任务的最小文件集，可增不可删。

```text
apps/relay/
├── src/
│   ├── bootstrap/{main.ts, container.ts, http.ts（Fastify 构建与中间件注册）, workers.ts, shutdown.ts}
│   ├── core/
│   │   ├── config/{schema.ts, load.ts}
│   │   ├── db/{connection.ts, migrate.ts, kysely-types.ts（由 0001 生成）, unit-of-work.ts}   # Agent-Data
│   │   ├── logging/{logger.ts（pino，字段 traceId/tenantId/deviceId）, redact.ts}
│   │   ├── errors/{app-error.ts（code→httpStatus/retryable 映射 error-codes.json）, http-error-handler.ts}
│   │   ├── security/{crypto.ts（AES-256-GCM 封装凭据）, master-key.ts, hash.ts（argon2id、sha256）, csrf.ts}
│   │   ├── middleware/{trace.ts, security-headers.ts, rate-limit.ts, authenticate.ts, csrf.ts, tenant-context.ts,
│   │   │               permission.ts, emergency-gate.ts, idempotency.ts, access-log.ts}
│   │   ├── validation/ajv.ts                 # 从 @workfleet/contracts/generated 载入校验器
│   │   └── metrics/registry.ts               # Prometheus 文本
│   ├── shared/
│   │   ├── domain/{result.ts, clock.ts, ids.ts（前缀+ULID，ADR-012）, entity.ts, domain-event.ts}
│   │   └── application/{event-bus.ts（DESIGN-007 §6）, wake-signal.ts（表即队列的内存唤醒）}
│   └── modules/
│       ├── identity/
│       │   ├── domain/{user.ts, password-policy.ts, web-session.ts, ports.ts(UserRepo, SessionRepo, PasswordHasher)}
│       │   ├── application/{register.ts, login.ts, logout.ts, current-principal.ts, switch-tenant.ts}
│       │   ├── interfaces/http/{routes.ts（/auth/*, /me*）}
│       │   ├── infrastructure/{user-repo.sqlite.ts, session-repo.sqlite.ts, argon2-hasher.ts}
│       │   └── index.ts                       # authenticate(), currentPrincipal()
│       ├── tenancy/
│       │   ├── domain/{tenant.ts, membership.ts, permission-matrix.ts（载入 permissions.json）, policy.ts（extraRules、projectScope）}
│       │   ├── application/{assert-permission.ts, list-members.ts, invitations/{create.ts}, update-role.ts, remove-member.ts, scope/filter-by-scope.ts}
│       │   ├── interfaces/http/routes.ts      # /members*
│       │   ├── infrastructure/{tenant-repo.sqlite.ts, membership-repo.sqlite.ts, invitation-repo.sqlite.ts}
│       │   └── index.ts                       # assertPermission(principal, action, resource)
│       ├── devices/
│       │   ├── domain/{device.ts, pairing-code.ts（8 位、10 分钟、一次性）, device-token.ts（256 bit，存 sha256）}
│       │   ├── application/{create-pairing-code.ts, claim.ts, revoke.ts, rotate-token.ts, primary/set-primary.ts, presence.ts}
│       │   ├── interfaces/http/routes.ts      # /devices*
│       │   ├── infrastructure/{device-repo.sqlite.ts, pairing-repo.sqlite.ts}
│       │   └── index.ts                       # resolveDevice(token), isOnline(deviceId), primaryDeviceOf(userId)
│       ├── projects/{domain/project.ts（depth≤3）, application/{create,update,tree,overview}.ts, interfaces/http/routes.ts, infrastructure/project-repo.sqlite.ts, index.ts}
│       ├── agents-registry/
│       │   ├── domain/{agent.ts（alias 规则）, alias.ts}
│       │   ├── application/{sync-from-node.ts（hello/agents.sync）, create.ts, update.ts, delete.ts, list.ts, list-input-adapters.ts}
│       │   ├── interfaces/{http/routes.ts, gateway/on-agents-sync.ts}
│       │   ├── infrastructure/agent-repo.sqlite.ts
│       │   └── index.ts                       # findAgentByAlias(tenantId, alias), getAgent(id)
│       ├── channels/
│       │   ├── domain/{channel.ts, capabilities.ts（合并 channel-kinds 默认值与适配器声明）, health.ts（状态机 §7.4）, bot-identity.ts}
│       │   ├── application/{registry.ts（kind→Factory）, start-channel.ts, stop-channel.ts, submit-credential.ts,
│       │   │               qr-login.ts, test-send.ts, on-inbound.ts（入站持久化入口）, identity-guard/check-unique.ts}
│       │   ├── interfaces/http/routes.ts      # /channels*, /adapters/channel
│       │   ├── infrastructure/
│       │   │   ├── channel-repo.sqlite.ts, credential-vault.ts（channels.credential_enc 读写）, token-store.sqlite.ts（channel_tokens）
│       │   │   └── adapters/{web/, wechat-clawbot/, feishu/, qq/, dingtalk/, telegram/, discord/}   # 每个目录：index.ts（Factory）、client.ts、inbound.ts、render.ts、capabilities.ts
│       │   └── index.ts                       # ChannelAdapter 端口类型、send(), onInbound()
│       ├── recipients/
│       │   ├── domain/{recipient.ts, quiet-hours.ts, bind-code.ts（6 位，TTL 见 DESIGN-011）}
│       │   ├── application/{resolve-or-create.ts, authorize.ts, start-bind.ts（/bind）, confirm-bind.ts, update.ts}
│       │   ├── interfaces/http/routes.ts
│       │   ├── infrastructure/recipient-repo.sqlite.ts
│       │   └── index.ts                       # resolveRecipient(channelId, platformId, scope)
│       ├── commands/                          # ownership-matrix 已列，architecture §4.1 未列，见 §11
│       │   ├── domain/{command.ts（载入 im-commands.json）, parser.ts}
│       │   ├── application/{execute.ts, handlers/{help,list,use,clear,stop,stop-all,status,history,bind,boss}.ts, approval-codes/parse-yn.ts}
│       │   └── index.ts                       # parse(text) → ParsedInput；execute(parsed, ctx)
│       ├── routing/
│       │   ├── domain/{route.ts（模式约束校验）, resolution.ts（选路结果值对象）, modes/{management,notification,team,supervisor}.ts}
│       │   ├── application/{route-inbound.ts（DESIGN-006 §2 算法）, fanout-outbound.ts, focus.ts, trace-reply.ts, dry-run.ts, device-select/select.ts, crud.ts}
│       │   ├── interfaces/http/routes.ts      # /routes*, /routes/dry-run
│       │   ├── infrastructure/{route-repo.sqlite.ts, focus-repo.sqlite.ts}
│       │   └── index.ts                       # route(inbound), fanout(outboundMessage)
│       ├── conversations/
│       │   ├── domain/{conversation.ts（generation、displayId）, message.ts（append-only）, display-id.ts}
│       │   ├── application/{get-or-create.ts, append-message.ts, clear.ts, cancel.ts, list.ts, history/{search.ts, fetch-transcript.ts}}
│       │   ├── interfaces/{http/{routes.ts, history-routes.ts}, stream/web-stream.ts（/api/v1/stream）}
│       │   ├── infrastructure/{conversation-repo.sqlite.ts, message-repo.sqlite.ts, fts-worker.ts（worker_threads，ADR-009）}
│       │   └── index.ts                       # appendMessage(), searchHistory()
│       ├── delivery/
│       │   ├── domain/{delivery.ts（状态机）, retry-policy.ts, token-bucket.ts, quota-budget.ts（DEC-023）, merge-window.ts（DEC-017）}
│       │   ├── application/{enqueue.ts, worker.ts（§7.1）, replay.ts, render.ts（IR→RenderedPayload，DESIGN-007 §4）}
│       │   ├── interfaces/http/routes.ts      # /deliveries*
│       │   ├── infrastructure/delivery-repo.sqlite.ts
│       │   └── index.ts                       # enqueue(messageId, recipientIds)
│       ├── approvals/
│       │   ├── domain/{approval.ts, short-code.ts（1..99 tenant 内 pending 唯一）, held.ts}
│       │   ├── application/{request.ts, decide.ts, expire.ts（§7.2）, release-held.ts, text-codes/map-yn.ts}
│       │   ├── interfaces/{http/routes.ts, gateway/on-approval-request.ts}
│       │   ├── infrastructure/{approval-repo.sqlite.ts, held-repo.sqlite.ts}
│       │   └── index.ts                       # requestApproval(), hasPending(agentId)
│       ├── orchestration/
│       │   ├── domain/{barrier.ts（状态机 DESIGN-006 §5）, summary.ts}
│       │   ├── application/{open-barrier.ts, submit.ts, close.ts, timeout.ts（§7.3）}
│       │   ├── interfaces/{http/routes.ts, gateway/on-barrier-submit.ts}
│       │   ├── infrastructure/barrier-repo.sqlite.ts
│       │   └── index.ts                       # openBarrier(), onAgentOutput()
│       ├── permissions-filter/
│       │   ├── domain/{filter-rule.ts, mask.ts（full/partial/hash）, evaluate.ts}
│       │   ├── application/{filter-outbound.ts, crud.ts}
│       │   ├── interfaces/http/routes.ts      # /filter-rules*
│       │   ├── infrastructure/filter-repo.sqlite.ts
│       │   └── index.ts                       # filterOutbound(message, recipient, route)
│       ├── audit/
│       │   ├── domain/audit-entry.ts
│       │   ├── application/{record.ts, query.ts, twin-forward/forward.ts（twin.capture 下发）}
│       │   ├── interfaces/{http/routes.ts, events/subscribers.ts（订阅领域事件写审计）}
│       │   ├── infrastructure/audit-repo.sqlite.ts
│       │   └── index.ts                       # record()
│       ├── notifications/
│       │   ├── domain/{priority.ts, fallback-policy.ts}
│       │   ├── application/{notify.ts, health-alert.ts, push-send.ts}
│       │   ├── interfaces/{http/routes.ts（push-subscriptions、vapid key）, events/subscribers.ts}
│       │   ├── infrastructure/{push-repo.sqlite.ts, webpush/sender.ts}
│       │   └── index.ts                       # notify(tenantId, priority, body, opts)
│       ├── node-gateway/
│       │   ├── domain/{frame.ts（envelope 类型）, seq-window.ts, link-state.ts}
│       │   ├── application/{handshake.ts, send-to-node.ts, on-frame.ts（按 type 分派）, replay-outbox.ts, heartbeat.ts}
│       │   ├── interfaces/ws/server.ts         # /api/v1/node-gateway
│       │   ├── infrastructure/{node-outbox-repo.sqlite.ts, dedupe-repo.sqlite.ts}
│       │   └── index.ts                       # sendToNode(deviceId, type, payload), onNodeFrame(type, handler)
│       └── system/
│           ├── application/{health.ts, emergency/{stop-all.ts, resume.ts}, config-io/{export.ts, import.ts}, doctor.ts, retention.ts（§7.7）}
│           ├── interfaces/http/routes.ts      # /health, /emergency/*, /config/*
│           └── index.ts
├── tests/{unit/modules/**, integration/modules/**}
└── package.json
```

## 4. 各模块四层内容摘要
| 模块 | domain（纯规则） | application（用例） | interfaces | infrastructure（表） |
|---|---|---|---|---|
| identity | 邮箱规范化（NOCASE）；密码 ≥10 位；会话 14 天滑动（session-claims） | register 同时建 personal tenant + admin membership + web 渠道与本人接收人（§11 W-1）；login 写 `web_sessions(id_hash)`，Cookie 只放不透明 id | `/auth/*`、`/me`、`/me/switch-tenant` | users、web_sessions |
| tenancy | 权限矩阵 + extraRules + projectScope 判定；跨 tenant 一律 404 | assertPermission、成员 CRUD、邀请（token 存 sha256） | `/members*` | tenants、memberships、invitations |
| devices | 配对码 8 位（字符集 Crockford base32 去 0/O/1/I 混淆，推断）；令牌轮换保留 `prev_token_hash` 至下次成功握手 | claim：校验码→建 device→返回明文令牌一次；revoke：置 revoked_at 并关闭 ws（close 4401） | `/devices*` | devices、pairing_codes |
| projects | depth = parent.depth+1 ≤ 3；slug 唯一 | 树查询（一次取全 tenant 扁平列表）、overview 聚合未读/运行中/待审批 | `/projects*` | projects |
| agents-registry | alias `^[a-z][a-z0-9-]{0,15}$`（设计值）且 tenant 内唯一 → `ALIAS_TAKEN` | Web 创建 → 写库 + 下发到节点（**无对应帧，见 §11 W-3**）；hello/agents.sync 时以节点为准合并运行态 | `/agents*`、`/adapters/input` | agents |
| channels | capabilities 合并：契约默认（channel-kinds.v1）← 适配器声明 ← 实测覆盖；健康状态机 | 注册表、启动/停止、凭据提交（AES-GCM 加密写 `credential_enc`）、Bot 身份唯一（`ux_channels_bot_identity` 冲突 → `BOT_IDENTITY_CONFLICT`） | `/channels*` | channels、channel_tokens |
| recipients | 默认 `authorized=false`（DEC-030）；静默时段判定 | 入站时 resolve-or-create；/bind 发码；控制台确认 | `/recipients*` | recipients |
| commands | 指令语法表 = im-commands.json；前缀 `/` 与 `／`；文本 NFKC 规范化后匹配 | 每条指令一个 handler（DESIGN-005 §2） | 无 HTTP（经 messages 端点与渠道入站调用） | — |
| routing | 模式约束（route.schema 描述）；选路确定性（DEC-005） | DESIGN-006 全部算法 | `/routes*`、`/routes/dry-run` | routes、route_sources、route_targets、route_filters、recipient_focus |
| conversations | generation 只增；displayId `^[A-Z]{2,4}-\d{1,6}$`；消息 append-only | get-or-create（`ux_conversations_active` 保证唯一）、append、clear、history | `/conversations*`、`/history/search`、`/stream` | conversations、display_id_counters、messages、messages_fts |
| delivery | 状态机 queued→sending→sent / failed→(重试)→dead / suppressed；重试表；令牌桶；微信额度预算 | enqueue（批量写，≤50/事务）、worker、replay | `/deliveries*` | deliveries |
| approvals | shortCode 分配（最小可用 1..99）；超时 = 拒绝；high 风险需 decide_high 或设备所有者 | request、decide（IM Y/N 与 Web 同一路径）、expire、release-held | `/approvals*` | approvals、held_messages |
| orchestration | 屏障状态机；缺失来源标注 | open/submit/close/timeout | `/barriers*` | barriers、barrier_submissions |
| permissions-filter | allow_fields / mask_fields / drop_message；多规则按 `route_filters.ord` 顺序叠加 | filterOutbound（出站前最后一道） | `/filter-rules*` | filter_rules、route_filters |
| audit | append-only（触发器禁止 UPDATE/DELETE） | 订阅事件写审计；twin.capture 转发 | `/audit` | audit_log |
| notifications | p0 立即、p1 高、p2 普通、p3 摘要；备用渠道选择 | notify、渠道健康告警、Web Push | `/push-subscriptions`、`/push/vapid-public-key` | push_subscriptions |
| node-gateway | seq/ack 窗口；心跳 20 s，60 s 无帧离线（ADR-005） | 握手、发送（先落 node_outbox 再发）、按 type 分派、续传 | `/api/v1/node-gateway` | node_outbox、node_inbox_dedupe、devices.relay_seq/last_acked_node_seq |
| system | — | health、急停、配置导入导出、doctor、保留期清理 | `/health`、`/emergency/*`、`/config/*` | tenants.emergency_stopped_at |

## 5. 请求生命周期
### 5.1 HTTP（以 `POST /api/v1/conversations/{id}/messages` 为例）
```text
TLS 反代 → 127.0.0.1:5101
 onRequest   trace → security-headers → rate-limit(IP) → authenticate(session) → csrf → tenant-context
 preValidation  ajv（请求体 schema 来自 openapi 引用）→ 400 VALIDATION_FAILED
 preHandler  permission(x-permission=agent.prompt, resource=conversation) → emergency-gate → idempotency(查 idempotency_keys)
 handler     conversations.interfaces → application.sendWebMessage:
               BEGIN IMMEDIATE
                 messages.insert(inbound, idempotency_key='web:'+principal+':'+Idempotency-Key)
               COMMIT → bus.publish(message.received)
               routing.route(inbound) → (DESIGN-006) → gateway.sendToNode / held / 回执
             返回 202 + message
 onSend      idempotency 写入（principal+key → status+body，24 h）
 onResponse  access-log（无请求体）、metrics（直方图 http_request_duration_seconds{route,status}）
 onError     AppError → error.schema 体（code/message/traceId/retryable）；未知错误 → INTERNAL（日志带栈）
```
### 5.2 IM 入站（渠道适配器 → 中转）
```text
adapter 收到平台事件
 → channels.application.onInbound(evt):
     BEGIN IMMEDIATE
       recipients.resolveOrCreate(channelId, platformId, scope)
       messages.insert(direction=inbound, idempotency_key = channelId+':'+platformMessageId)   # 冲突=重复，直接 ACK 返回
       channel_tokens.upsert（如微信 context_token：刷新 refreshed_at、sent_since_refresh=0）
     COMMIT
 → adapter.ackInbound?(evt)（平台要求的回执/typing，≤3 s，REQ-NF-001）
 → bus.publish(message.received)
 → commands.parse → routing.route（DESIGN-006）
```
关键点：**先持久化再回执**（WF-ARCH §6.1 步骤 1）；路由失败不影响已持久化的入站，失败经 `system` 消息回给发送人。

### 5.3 节点帧（node → relay）
```text
ws message → JSON.parse → ajv(envelope + payload) 失败 → error 帧(code=VALIDATION_FAILED, refSeq)
 → dedupe：INSERT OR IGNORE node_inbox_dedupe(device_id, idempotency_key)；已存在 → 只 ack
 → on-frame 分派：agent.output→conversations+routing.fanout；approval.request→approvals；agent.status/agents.sync→agents-registry；
                  history.result→挂起的 Promise；barrier.submit→orchestration；error→日志+按 code 处理
 → 处理完成后更新 devices.last_acked_node_seq，并按“每 50 帧或 200 ms”发送累积 ack（设计值）
```

## 6. 中间件顺序（Fastify hooks，自上而下执行）
| # | 中间件 | hook | 作用 | 失败码 |
|---|---|---|---|---|
| 1 | trace | onRequest | 读取/生成 `traceId`（`trc_`+ULID）；写入 `reply.header('X-Trace-Id')` 与 logger child | — |
| 2 | security-headers | onRequest | HSTS（由反代亦可）、`X-Content-Type-Options`、CSP（`default-src 'self'`，`connect-src 'self' wss:`）、`Referrer-Policy` | — |
| 3 | rate-limit | onRequest | 令牌桶：按 IP（认证类端点 `auth/*`、`devices/claim` 10 次/分钟，其余 600 次/分钟，设计值） | 429 RATE_LIMITED |
| 4 | authenticate | onRequest | `x-auth=session`：Cookie→sha256→web_sessions（未过期、未吊销），滑动续期；`x-auth=device`：Bearer→sha256→devices.token_hash/prev_token_hash；设备令牌访问非 node-gateway → 401（forbiddenPaths） | 401 UNAUTHENTICATED / 403 DEVICE_REVOKED |
| 5 | csrf | onRequest | 非 GET 且 x-auth=session：`X-CSRF-Token` == session.csrf（常量时间比较） | 403 FORBIDDEN |
| 6 | tenant-context | onRequest | 构造 `Principal{userId, tenantId, role, projectScope}` | — |
| 7 | ajv 校验 | preValidation | 请求体/参数/查询 | 400 VALIDATION_FAILED |
| 8 | permission | preHandler | 读取路由 `x-permission`；viewer 非 GET 一律 403（notification.subscribe 除外）；资源归属检查在 handler 内调用 `assertPermission(…, resource)` | 403 FORBIDDEN / 404 NOT_FOUND |
| 9 | emergency-gate | preHandler | tenant 已急停时，`agent.prompt`、`route.write`、`channel.*` 写操作返回 423；`emergency.resume`、只读不受影响 | 423 EMERGENCY_STOPPED |
| 10 | idempotency | preHandler / onSend | 带 `Idempotency-Key` 的 POST：命中则直接返回首次结果（契约 openapi 描述：24 h） | — |
| 11 | access-log + metrics | onResponse | 不记录请求体与 Cookie；`redact.ts` 统一脱敏 | — |
| 12 | error handler | setErrorHandler | AppError → error-codes 映射 | — |

## 7. 后台工作者
所有工作者遵循同一骨架：**表即队列 + 内存唤醒 + 兜底轮询**（DEC-013）：
```ts
class Worker { constructor(private name, private tick: () => Promise<number>, private idleMs, private wake: WakeSignal) {}
  async loop(signal) { while (!signal.aborted) {
      const n = await this.tick();              // 返回本轮处理条数
      if (n === 0) await this.wake.wait(this.idleMs, signal);   // 被 enqueue 唤醒或超时
  } } }
```
### 7.1 DeliveryWorker（delivery）
- 取件：`SELECT … FROM deliveries WHERE status IN ('queued','failed') AND next_attempt_at <= :now ORDER BY next_attempt_at LIMIT 50`（命中 `ix_deliveries_due`）→ 同一事务把这批置 `sending`（单写者，无需 SKIP LOCKED）。
- 每条：急停检查（tenant.emergency_stopped_at 非空 → 保持 queued，不发）→ 静默时段（p0 例外）→ 渲染（DESIGN-007 §4，结果写 `rendered_payload`、`rendered_as`）→ 渠道令牌桶（DESIGN-010 §5）→ 额度预算（微信）→ `adapter.send()`。
- 结果：成功 → `sent` + `deliveries.platform_message_id`（一条出站消息对多个接收人有多个平台 id，故存于 deliveries 而非 messages；回复溯源查询见 DESIGN-006 §3）→ 发布 `delivery.sent`；失败按重试表：

| 错误类别 | 判定 | 重试 | 终态 |
|---|---|---|---|
| 网络/5xx/超时 | adapter 抛 `TransientError` | 2 s、10 s、60 s、5 min、30 min（交互类首次 ≤2 s，DEC-024） | 第 6 次失败 → `dead` + `delivery.failed` |
| 429/限速 | `RateLimitedError(retryAfterSec)` | 按 retryAfter；不计入次数上限 | — |
| 凭据失效 | `CredentialExpiredError` | 不重试；渠道健康 → expired；消息转备用渠道（§7.4） | `failed`（等待凭据恢复后由 replay 触发） |
| 额度耗尽 | `QuotaExhaustedError` | 不重试；p0 走备用渠道，其余保持 queued 直到下次入站刷新额度 | — |
| 能力不支持/内容非法 | `PermanentError` | 不重试 | `dead` |
- 合并窗口（DEC-017）：p3 的 `final/status` 消息对同一 recipient 不立即投递，进入 merge-window（60 min 或 ≥5 条或额度剩余 ≤3 时生成一条 digest 消息，原 deliveries 置 `suppressed` 并在 `filters_applied` 记 `merged_into:<msgId>`）。数值来自 V0.0.2 §1.5，部分确认。

### 7.2 ApprovalExpiryWorker（approvals）
- 每 5 s：`SELECT id FROM approvals WHERE status='pending' AND expires_at <= :now LIMIT 100`（`ix_approvals_pending`）。
- 每条事务：`status='expired', decided_at=now` → 发 `approval.decision` 帧给节点，`optionId` = 选项中 `kind='reject'` 的第一个（契约：超时默认拒绝）→ `approval.decided` 事件 → 释放 held（按 held_at 顺序重新进入路由，DESIGN-006 §6）→ 更新 IM 卡片（可编辑渠道显示“已过期”，`APPROVAL_EXPIRED`）。
- 过期时长默认值见 DESIGN-011（契约未规定，§11 W-6）。

### 7.3 BarrierTimeoutWorker（orchestration）
- 每 5 s：`status='open' AND opened_at + timeout_sec*1000 <= now`（无专门索引，open 屏障数量小，推断）。
- 关闭：`status='timed_out'` → 生成汇总消息（已收来源各一节 + `callout(warn)` 列出缺失别名）→ `barriers.summary_message_id` → 按路由 fanout + 过滤 → `barrier.closed`。

### 7.4 ChannelHealthProbe（channels / notifications）
- 健康状态机（`channel.health` 枚举）：
```text
disabled --start ok--> healthy
healthy --连续 3 次收发失败 / 长连接断开--> degraded --恢复--> healthy
degraded --断开持续 ≥30 s--> disconnected --重连成功--> healthy
任意 --401/403/凭据失效信号--> expired --重新提交凭据/扫码--> healthy
任意 --用户停用--> disabled
```
- 探测：适配器自报（长连接 close、长轮询异常、发送错误）为主；工作者每 15 s 调 `adapter.health()` 汇总，并检查 `inboundMode=long_poll` 渠道最近一次轮询返回时间（>2×轮询超时视为断开）。
- 状态变化 → `channel.health_changed` → notifications.health-alert：p0 告警发给 tenant admin 的**备用渠道**（选择顺序：Web Push → 该用户其他 healthy 渠道上已授权的 direct 接收人；不选同一故障渠道），目标 60 s 内（REQ-F-030）。
- 微信额度：`channel_tokens.sent_since_refresh` 达到 `maxMessagesPerInbound-3` 时，在下一条出站尾部附续期提示（REQ-F-009、DESIGN-005 §7）。
- Bot 唯一消费者（REQ-F-031）：适配器检测到“被顶掉/消息被他处消费”信号（平台具体信号证据不足，TASK-207 实测）→ health=degraded + p0 告警 `BOT_IDENTITY_CONFLICT`。

### 7.5 PushSender（notifications）
- 对 p0/p1（`push_subscriptions.min_priority` 过滤）发送 Web Push（VAPID）；HTTP 404/410 → 删除该订阅；其他失败 `failed_count+1`，≥5 次删除（设计值）。

### 7.6 NodeOutboxReplayer（node-gateway）
- 连接建立时：从 `node_outbox` 取 `seq > welcome 时节点报告的 lastAckedRelaySeq AND acked_at IS NULL` 按 seq 顺序重发（ADR-005）。
- 运行时：未 ack 帧 30 s 后重发一次（同 seq、同 idempotencyKey）；在途窗口上限见 DESIGN-010 §6。

### 7.7 RetentionSweeper（system）
每小时一次，单批 ≤500 行，详见 DESIGN-004 §4：过期 web_sessions、used/expired pairing_codes、24 h 前 idempotency_keys、7 天前已 ack 的 node_outbox 与 node_inbox_dedupe、超过保留期的 attachments（先软删 7 天后物理删文件）。

## 8. node-gateway 连接生命周期
```text
节点 → GET /api/v1/node-gateway (Upgrade, Authorization: Bearer <deviceToken>)
 authenticate(device) 失败 → HTTP 401；revoked → 403 DEVICE_REVOKED
 ← 节点首帧必须是 hello（5 s 内，否则 close 4400）
   protocolVersion != 1 → error(PROTOCOL_VERSION_UNSUPPORTED) + close 4426
   若用 prev_token_hash 认证成功 → 清空 prev_token_hash（轮换完成）
 → welcome{deviceId, lastAckedNodeSeq=devices.last_acked_node_seq, serverTime, heartbeatSec:20}
 → 节点从 lastAckedNodeSeq+1 续传；中转从 hello.lastAckedRelaySeq+1 续传（§7.6）
 → agents-registry.syncFromNode(hello.agents) → device.online 事件（幂等键 deviceId+connectedAt）
 心跳：双方每 20 s 发 ping；60 s 未收到任何帧 → close 4408 → device.offline
 同一 deviceId 新连接到来 → 旧连接 close 4409（单连接）
```

## 9. 事务与事件约定
- 写操作在 `unitOfWork(async tx => …)` 内完成（better-sqlite3 同步事务，`BEGIN IMMEDIATE`），**事件在 COMMIT 之后发布**；处理器必须幂等（domain-events.json `$comment`）。
- 跨模块写不在一个事务中串联多个模块的用例；需要原子性的组合（入站消息 + recipient + token）由入口模块的应用服务调用对方仓储端口完成，并在 DESIGN-007 §5 声明该端口为公开端口。
- 进程内事件丢失（崩溃在 COMMIT 与 publish 之间）的补偿：所有关键副作用都有“表即队列”的兜底（deliveries、node_outbox、approvals 过期扫描），事件只用于加速与审计（推断，可推翻）。

## 10. 错误映射
`core/errors/app-error.ts`：`new AppError('DEVICE_OFFLINE', msg, details)` → 查 `error-codes.json` 得 `httpStatus`、`retryable`；未登记的 code 在启动自检时报错（防止漂移）。协议 `error` 帧复用同一码表（契约 README）。

## 11. 与契约的差异 / 待办
| # | 发现 | 处理（不改契约） |
|---|---|---|
| W-1 | Web 渠道的 channel 行与“每个用户一个 recipient”在契约/迁移中未说明，但 `conversations` 的唯一性依赖 `(agent, route, recipient)` | 设计：tenant 创建时建一条 `kind='web'` 渠道；用户首次登录时建 `scope=direct, platform_id=userId, authorized=1, linked_user_id=userId` 的接收人 |
| W-2 | architecture §4.1 无 `commands` 模块，ownership-matrix 有 `apps/relay/src/modules/commands/**` | 按矩阵建独立模块；建议 architecture 补一行 |
| W-3 | `POST /agents`“下发到节点创建”，但 envelope `type` 枚举中**没有 relay→node 的智能体增删改帧**（`agents.sync` 只有 node 方向） | 阻塞 TASK-026 的“下发”部分；临时方案：智能体只能在本机控制台创建后经 agents.sync 上报，Web 端仅可改别名/项目（仍需帧）；需契约新增 `agents.upsert`/`agents.delete`（relay 方向） |
| W-4 | 节点被吊销后的 close code、单连接替换等 ws 关闭码未入契约 | 本文 §8 定义 4400/4401/4408/4409/4426，建议入契约 |
| W-5 | 审批取消（智能体 cancel 后 ACP 权限请求失效）无对应帧，approval.status 有 `cancelled` | 临时：节点发 `error` 帧 `code=APPROVAL_EXPIRED, refSeq=<approval.request 的 seq>` 由中转置 cancelled；建议新增 `approval.cancel` 帧 |
| W-6 | 审批超时时长、/bind 码有效期、屏障默认超时契约未给 | DESIGN-011 给默认值，可配置 |
| W-7 | `approval.decision.decidedBy` 为任意 string，实体为 userId\|recipientId | 中转写入时只放 `usr_`/`rcp_` id |
| W-8 | 中转 metrics 端口未分配（5104 分给节点） | DESIGN-011：中转默认在 5101 的 `/metrics`，仅允许无 `X-Forwarded-For` 的回环请求；反代配置拒绝 `/metrics` |
| W-10 | 回复溯源需按 `(channel_id, platform_message_id)` 查**出站投递**，但 `deliveries.platform_message_id` 无索引（`ux_messages_platform` 只覆盖 messages 行） | 请求 Agent-Data 追加迁移 0002：`CREATE INDEX ix_deliveries_platform ON deliveries(channel_id, platform_message_id) WHERE platform_message_id IS NOT NULL`；在此之前全表扫描仅可用于测试 |
| W-9 | `messages`、`deliveries`、`barriers` 表无 `tenant_id`，租户隔离需经 conversations/routes 连接 | 仓储层统一经父表校验 tenant；若性能不足由 Agent-Data 追加迁移 |
