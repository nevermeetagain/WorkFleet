---
id: DESIGN-016
type: design
title: 通信协议（中转↔节点 WSS 帧协议；ACP 使用面与帧映射；IM 侧收发模式）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - ADR-005、ADR-006、ADR-007、ADR-012
  - DEC-004/012/022/037/040/048/051
  - REQ-NF-001/003/004、REQ-F-005/006/019/020/033
  - packages/contracts/protocol/envelope.schema.json、protocol/frames/*.schema.json
  - packages/contracts/errors/error-codes.json、events/domain-events.json
  - packages/contracts/identity/device-token-claims.schema.json
  - packages/contracts/api/relay.openapi.json（GET /api/v1/node-gateway、POST /api/v1/devices/claim）
  - database/migrations/relay/0001_init.sql（devices.relay_seq/last_acked_node_seq、node_outbox、node_inbox_dedupe）
  - database/migrations/node/0001_init.sql（relay_links.node_seq/last_acked_relay_seq、relay_outbox、relay_inbox_dedupe、pending_permissions）
  - V0.0.2/30-协议与端点/01（ACP v1 方法与语义）、03（IM 收发机制）
---

# DESIGN-016：通信协议

> 证据标签：已确认 / 部分确认 / 证据不足 / 推断 / 待实测。帧名、字段名以 `packages/contracts/protocol` 为唯一源，本文只规定**行为**。

## 1. 连接与鉴权
| 项 | 约定 | 依据 |
|---|---|---|
| URL | `wss://{relayHost}/api/v1/node-gateway`（公网只 443，经反代到 127.0.0.1:5101） | relay.openapi、DEC-051 |
| 鉴权 | HTTP Upgrade 请求头 `Authorization: Bearer <deviceToken>`；中转按 `SHA-256(token)` 查 `devices.token_hash`（轮换宽限期内也接受 `prev_token_hash`，DESIGN-019 §3.3） | ADR-006、device-token-claims |
| 失败 | 握手前返回 HTTP：无/错令牌 401 `UNAUTHENTICATED`；已吊销 403 `DEVICE_REVOKED`；不升级为 WS | error-codes.json |
| 编码 | 文本帧，UTF-8 JSON，一个 WS 消息 = 一个 envelope；不用二进制帧、不开 permessage-deflate（推断：避免压缩炸弹与 CPU；可在实测后开启） |
| 帧上限 | 序列化后 ≤ 1 MiB（`ws` 的 `maxPayload = 1_048_576`）；超出 → 对端回 `error{code:PAYLOAD_TOO_LARGE}` 并关闭 4013 | ADR-005、envelope 描述 |
| 校验 | 收到的每帧先过 ajv（envelope + payload 子 schema）；失败 → `error{code:VALIDATION_FAILED, refSeq}`，并按 §8 处理 | ADR-002 |
| 多中转 | 节点每条 `relay_links` 一条独立连接、独立令牌（钥匙串 `wf:relay-token:{relayLinkId}`）、独立 seq 空间、独立 outbox | DEC-048、node 0001 |
| 同设备重复连接 | 新连接握手成功后，中转以 close 4001 关闭旧连接（“最后连接者胜”） | 推断 |

## 2. Envelope 字段语义
| 字段 | 规则 |
|---|---|
| `v` | 固定 1 |
| `seq` | `hello/welcome/ack/ping` 恒为 0；其余所有类型（含 `error`）从 1 起、每方向每连接对（device×relay）单调 +1，**跨重连延续**（持久化：中转 `devices.relay_seq`、节点 `relay_links.node_seq`） |
| `idempotencyKey` | 业务幂等键（§5.2 表），与 seq 无关；同一业务动作重发（包括 outbox 重建后）必须相同 |
| `traceId` | `trc_` + ULID；同一用户动作链路保持不变（DESIGN-018 §8） |
| `sentAt` | 发送方时钟 RFC 3339 毫秒（ADR-012）；只用于诊断/时钟偏差估计，不参与排序 |
| `payload` | 对应 `frames/{type}.schema.json` |

帧方向（frames 描述字段，已确认契约）：
| 方向 | 帧 |
|---|---|
| node → relay | `hello`、`agent.output`、`agent.status`、`approval.request`、`agents.sync`、`history.result`、`barrier.submit` |
| relay → node | `welcome`、`agent.prompt`、`agent.cancel`、`agent.clear`、`approval.decision`、`history.query`、`emergency.stop`、`emergency.resume`、`twin.capture` |
| 双向 | `ack`、`ping`、`error` |

## 3. 握手与续传

### 3.1 时序（文字）
```text
Node                                                        Relay
 |—— TCP+TLS+HTTP Upgrade (Bearer token) ——————————————————▶|  校验令牌；失败 → 401/403，结束
 |◀————————————————————————— 101 Switching Protocols ———————|  启动 hello 计时器 10 s
 |—— hello{seq:0, protocolVersion:1, nodeVersion, os,       |
 |          lastAckedRelaySeq:R, agents:[…]} ——————————————▶|  ① protocolVersion≠1 → error{PROTOCOL_VERSION_UNSUPPORTED}(seq 递增) → close 4026
 |                                                          |  ② 踢旧连接(4001)；devices.last_seen_at=now；os/nodeVersion 更新
 |                                                          |  ③ upsert agents（等同 agents.sync，以 hello.agents 为全量）
 |                                                          |  ④ node_outbox 中 seq ≤ R 且未 ack → 标记 acked_at=now（节点已收）
 |◀—— welcome{seq:0, deviceId, lastAckedNodeSeq:N,          |
 |            serverTime, heartbeatSec:20} ——————————————————|  ⑤ 发 domain event device.online（key deviceId+connectedAt）
 |  节点：relay_outbox 中 seq ≤ N → acked；                   |
 |  按 seq 升序重发 seq > N 的未 ack 帧（续传）————————————————▶|  中转：同样按 seq 升序重发 node_outbox 中 seq > R 的帧
 |◀———————————————————————————————— 续传帧（seq = R+1 …）————|
 |—— ack{upToSeq:…} ⇄ ack{upToSeq:…}  正常收发 ————————————————|
```
- `serverTime` 用于节点估算时钟偏差 `skew = serverTime - (发送hello时刻+RTT/2)`；|skew| > 120 s 时节点 p2 提示校时（推断）；审批过期等判定一律以**中转时钟**为准。
- hello 10 s 未到 → close 4002。welcome 10 s 未到（节点侧）→ 关闭重连。
- 续传期间新业务帧照常追加在 outbox 尾部，保证全序。

### 3.2 节点重连退避
`delay = min(60 s, 1 s × 2^attempt) × (0.8 + 0.4 × random)`；连接稳定 ≥ 60 s 后 attempt 归零。收到 401/403 不重试，标记 `relay_links.status='revoked'` 并在本机控制台提示重新配对。收到 close 4026 不重试，提示升级。

### 3.3 中转重启
中转从 `node_outbox`（未 ack）与 `devices.relay_seq` 恢复；节点按 §3.2 重连，hello 带 `lastAckedRelaySeq` → 双向续传。REQ-NF-003（断线 10 分钟内不丢不重）由“outbox 持久化 + seq 续传 + 接收端 dedupe + 外发投递幂等（deliveries 唯一键 message_id+recipient_id）”共同保证。

## 4. seq / ack
### 4.1 发送端
```text
send(type, payload, idemKey):
  BEGIN
    seq = ++outSeq（持久化到 devices.relay_seq / relay_links.node_seq）
    INSERT outbox(seq, frame_json, created_at)
  COMMIT
  if 连接在线 且 未超出发送窗口(§6)：ws.send(frame)
```
### 4.2 接收端
```text
onFrame(f):
  validate(f)  失败 → §8
  if f.seq == 0: 控制帧，直接处理（hello/welcome/ack/ping）
  elif f.seq <= lastReceivedSeq: 重复（续传重叠），丢弃，但仍触发 ack
  elif f.seq == lastReceivedSeq + 1:
      BEGIN
        if exists dedupe(idempotencyKey): 跳过业务处理（幂等命中）
        else: INSERT dedupe; 业务处理（写库/入队）
        lastReceivedSeq = f.seq（持久化：中转 devices.last_acked_node_seq；节点 relay_links.last_acked_relay_seq）
      COMMIT
      scheduleAck()
  else (gap): WSS 基于 TCP 有序，出现间隙只可能是对端缺陷 → 发 error{code:INTERNAL, refSeq:f.seq} 并 close 4009；重连后从 lastReceivedSeq+1 续传自愈
```
- “处理后再 ack”：业务落库与 lastReceivedSeq 在同一事务，ack 只确认已持久化的帧 → 至少一次。
- `scheduleAck()`：累积 ack，满足任一即发送 `ack{upToSeq: lastReceivedSeq}`：距上次 ack 已收 32 帧；或 200 ms 定时器到期；或收到 `ping`。
- 收到 `ack{upToSeq:U}`：outbox 中 seq ≤ U 标记 acked（清理见 DESIGN-014 §7）。U 大于已发送最大 seq → 视为对端缺陷，忽略并记 warn。

## 5. 去重
### 5.1 两层
| 层 | 作用范围 | 实现 |
|---|---|---|
| seq | 同一连接对的续传重叠 | §4.2 `seq <= lastReceivedSeq` 丢弃 |
| idempotencyKey | 业务重复（outbox 重建、令牌轮换后重发、中转 Web 请求重试） | 中转 `node_inbox_dedupe(device_id, idempotency_key)`、节点 `relay_inbox_dedupe(relay_link_id, idempotency_key)`，保留 7 天 |
| 业务唯一键 | 最终防线 | 中转 `messages.idempotency_key` 唯一、`deliveries(message_id, recipient_id)` 唯一；节点 `prompt_queue.message_id` 唯一 |

### 5.2 idempotencyKey 规范（≤200 字符）
| 帧 | 键 |
|---|---|
| agent.prompt | `prompt:{messageId}` |
| agent.cancel | `cancel:{conversationId}:{ulid}` |
| agent.clear | `clear:{conversationId}:{newGeneration}` |
| agent.output | `out:{messageId}` |
| agent.status | `status:{agentId}:{ulid}`（状态类：接收端按 `sentAt` 只保留最新，旧的直接丢弃） |
| approval.request / approval.decision | `apr:{approvalId}` / `dec:{approvalId}` |
| agents.sync | `sync:{ulid}` |
| history.query / history.result | `hq:{requestId}` / `hr:{requestId}` |
| emergency.stop / emergency.resume | `estop:{tenantId}:{atMs}` / `eres:{tenantId}:{atMs}`（与 domain event `emergency.stopped` 键一致） |
| twin.capture | `twin:{twinEventId}` |
| barrier.submit | `bar:{barrierId}:{agentId}` |
| error | `err:{ulid}` |
| hello / welcome / ack / ping | `{type}:{ulid}`（schema 要求必填；接收端不去重） |

## 6. 心跳与背压
### 6.1 心跳（welcome.heartbeatSec = 20，ADR-005）
- 每方向：若 20 s 内未发送任何帧 → 发 `ping{}`（seq 0）。接收方以 `ack{upToSeq:lastReceivedSeq}` 回应（契约无 pong，ack 兼作应答）。
- 任一方向 **60 s 未收到任何帧** → 判定断线：close 4000；中转发 `device.offline`（key deviceId+lastSeenAt），设备状态 `offline`，后续 `agent.prompt` 仍入 outbox 并对用户回“设备离线，已排队”（`DEVICE_OFFLINE`，DEC-037）。
- 另启用 WS 协议层 ping（`ws.ping()`，30 s）仅用于探测半开 TCP，不改变上面判定（推断）。

### 6.2 背压
| 机制 | 参数 | 行为 |
|---|---|---|
| 在途窗口 | 未 ack 帧 ≤ 512 且 ≤ 8 MiB | 超出则暂停从 outbox 取帧发送（帧仍持久化） |
| socket 缓冲 | `ws.bufferedAmount` > 4 MiB | 暂停发送，`drain` 后恢复 |
| 接收速率 | 中转对单设备 > 200 帧/s | 暂停读取（`socket.pause()` 500 ms），依赖 TCP 背压 |
| 节点内源头 | 流式更新在节点聚合（DESIGN-013 §6） | 每轮次帧数中位 ≤ 5 |
| outbox 积压 | 中转单设备未 ack > 10,000 | 拒绝新 prompt（DESIGN-015 §8.1）+ p1 |
参数均为推断，TASK 压测回填。

## 7. 版本协商
- v1：`envelope.v = 1`、`hello.protocolVersion` const 1（契约）。中转只接受 1；否则 `error{code:PROTOCOL_VERSION_UNSUPPORTED}` + close 4026，节点提示升级（error-codes ui：“节点提示升级”）。
- 新增**可选**字段/新帧类型属于向后兼容演进：接收方遇到未知 `type` 应回 `error{VALIDATION_FAILED}` 但不断开（推断）；然而契约 envelope 的 `type` 是封闭枚举、payload `additionalProperties:false`，任何新增都需契约发版 → v2 需要真正的协商机制（差异 #1）。

## 8. 错误帧与关闭码
`error{code, message, refSeq?}`：`code` 必须取自 `errors/error-codes.json`；`refSeq` 指向引发错误的帧。
| 情形 | 错误码 | 是否关闭 |
|---|---|---|
| schema 校验失败（单帧） | VALIDATION_FAILED | 否；该帧视为已处理（推进 lastReceivedSeq 并 ack，避免无限重发毒帧），记死信日志 |
| 帧过大 | PAYLOAD_TOO_LARGE | 是 4013 |
| 协议版本 | PROTOCOL_VERSION_UNSUPPORTED | 是 4026 |
| seq 间隙 | INTERNAL | 是 4009 |
| 业务失败（如 prompt 指向已删除智能体） | AGENT_UNAVAILABLE / NOT_FOUND 等 | 否 |
| 已急停时收到 prompt | EMERGENCY_STOPPED | 否 |
| 设备在连接中被吊销 | DEVICE_REVOKED | 是 4003 |

| 关闭码 | 含义 | 节点动作 |
|---|---|---|
| 1000 | 正常关闭 | 重连 |
| 1001 | 中转停机/重启 | 重连（退避） |
| 4000 | 心跳超时 | 重连 |
| 4001 | 被同设备新连接替换 | 不重连（本实例很可能是旧进程），记录 warn |
| 4002 | hello 超时 | 重连 |
| 4003 | 设备吊销 | 停止，提示重新配对 |
| 4009 | seq 违规 | 重连 |
| 4013 | 帧过大 | 重连（问题帧应已改走附件） |
| 4026 | 协议版本不支持 | 停止，提示升级 |
| 4029 | 中转过载 | 重连（退避下限 30 s） |

## 9. 业务帧时序（文字）

### 9.1 对话一轮（含审批）
```text
User(IM/Web)   Relay                                   Node                          Agent 子进程(ACP)
  |─入站──────▶| 持久化 message(inbound)；回执(DESIGN-013)
  |            | route → conversation(cnv, gen)
  |            |── agent.prompt{agentId, cnv, gen, messageId, body, from} ─▶| INSERT prompt_queue（message_id 唯一）
  |            |◀──────────── ack ───────────────────────────────────────────|
  |            |◀── agent.status{agentId, running, queueDepth} ─────────────| Scheduler 启动轮次
  |            |                                                            |── session/prompt ──────────▶|
  |            |◀── agent.output{kind:status, …}（≤每2 s）──────────────────|◀── session/update(chunks) ───|
  |            |                                                            |◀── session/request_permission(id=42)
  |            |                                                            | INSERT pending_permissions(apr, acp_request_id=42)
  |            |◀── approval.request{approval(pending, shortCode, risk, options, expiresAt)} ─|
  |◀─审批卡/Y3──| approvals 入库；该智能体新入站 → held（DEC-012）
  |─点击/Y3────▶| 校验权限(DESIGN-019)/过期/已决
  |            |── approval.decision{approvalId, optionId, decidedBy} ──────▶| 查 pending_permissions → 回 ACP
  |            |                                                            |── {outcome:selected, optionId} ─▶|
  |            | 释放 held → 依次发 agent.prompt（入队，不打断当前轮）
  |            |◀── agent.output{kind:final, messageId, nativeSessionId, priority} ──|◀── prompt 响应 stopReason=end_turn
  |◀──结果─────| append message(outbound) → filterOutbound → deliveries
  |            |◀── agent.status{idle, queueDepth:0}
```
- 审批超时：中转定时扫描 `approvals(status=pending, expires_at<now)` → `expired` → 发 `approval.decision{optionId: <reject 类选项 id>, decidedBy:"system"}`（超时默认拒绝，DEC-011）。若 options 中无 reject 类选项 → 节点回 ACP `{outcome:"cancelled"}`（V0.0.2/04 §7）。
- 节点在发 approval.request 前若会话已被 cancel，则直接回 ACP cancelled，不上报。

### 9.2 取消 / 清空
```text
/stop z1 → Relay ── agent.cancel{agentId, cnv} ──▶ Node：若有进行中轮次 → ACP session/cancel（通知）；
          待答权限一并回 cancelled；队列中**该会话**未开始的 prompt 保留（/stop 只停当前轮，im-commands）
          ◀── agent.output{kind:status, status_card.state=failed, title:"已取消"} + agent.status{idle}
/clear  → Relay：conversations.generation+1（旧记录保留）── agent.clear{agentId, cnv, newGeneration} ──▶
          Node：取消进行中轮次 → 若支持 session/close 则关闭旧 session → 新 sessions(cnv, newGen) 行，
          下一次 prompt 时 session/new（ACP 无 /clear 原语，V0.0.2/01 C5）
```

### 9.3 智能体同步
节点智能体增删改、可执行文件探测结果变化 → `agents.sync{agents:[全量]}`；中转按 agentId upsert、对缺失项标 `unavailable`（不删除，删除只能由控制台发起，避免节点误报导致绑定丢失；推断）。

### 9.4 历史查询（DESIGN-012 §3.3）
`history.query{requestId, cnv, generation|null, limit}` → `history.result{requestId, entries}`；中转等待 10 s。

### 9.5 急停 / 恢复（DESIGN-018 §5）
```text
Relay：tenants.emergency_stopped_at=now；domain event emergency.stopped；对该 tenant 每台设备追加
       emergency.stop{reason}（在线设备立即发送，离线设备重连续传时送达）
Node：收到即 ①对所有会话 session/cancel ②暂停 Scheduler（prompt_queue 不出队）③待答权限全部回 cancelled
      ④总控停止 LLM 调用与定时器 ⑤Webhook(5102) 返回 423 → 回 agent.status(stopped) × N
恢复：emergency.resume{} → Node 恢复 Scheduler；急停期间队列中的 prompt 处理策略见 DESIGN-018 §5
```

### 9.6 分身采集与屏障
- `twin.capture{event}`：中转把**用户本人**在 IM/Web 发出的指令、审批、纠正、/命令转成 twin-event 发给该用户的**主设备**（`devices.is_primary`）；主设备离线则入 outbox 等续传（DESIGN-021）。
- `barrier.submit{barrierId, agentId, messageId}`：节点声明某条已发 `agent.output` 的 message 作为屏障提交；必须在对应 `agent.output` 之后发送（同连接全序保证 message 已存在）。

## 10. ACP 使用面（节点作为 ACP Client）
基于 ACP v1 稳定方法集（V0.0.2/01 §4.1，已确认）；v2 为特性开关（DEC-022），v1 不实现。

### 10.1 方法与参数
| ACP 方法 | 何时 | 参数要点 | 结果处理 |
|---|---|---|---|
| `initialize` | 子进程启动后第一条 | `protocolVersion: 1`；`clientCapabilities: { fs: { readTextFile: false, writeTextFile: false }, terminal: false }`（不声明 fs/terminal，V0.0.2/01 §7） | 记录 `agentCapabilities.loadSession`、`sessionCapabilities.{resume,list,close}`、`promptCapabilities`、`authMethods`；与 spec `supportsLoadSession` 不一致时以运行时为准并告警 |
| `authenticate` | 仅当 `authMethods` 非空且首个 `session/new` 返回需认证错误 | spec `auth=agent_managed`：不代登录，报 `AGENT_UNAVAILABLE`“请先在本机登录该工具”；`env_key`：从钥匙串注入环境变量后重启 | 需求 §8：WorkFleet 不代为登录 |
| `session/new` | 新会话 / `/clear` 后首次 prompt / 无法恢复时 | `cwd`: 智能体 `workdir`（或租约分配的 worktree 路径）；`mcpServers`: v1 传 `[]`（WorkFleet MCP 推送工具 5103 的接入格式**待实测**，DEC-022） | 返回 `sessionId` → `sessions.native_session_id`，随下一帧 `agent.output.nativeSessionId` 回报 |
| `session/resume` | 进程回收后恢复，且 `sessionCapabilities.resume` | `sessionId` = 已存 nativeSessionId，`cwd` | 不回放；历史以 WorkFleet 转录为准 |
| `session/load` | 无 resume 但 `loadSession=true` | 同上 | 回放的 `user_message_chunk/agent_message_chunk` 只写转录 role=system 标注“回放”，**不外发** |
| `session/prompt` | 每个出队的 prompt | `prompt: [ContentBlock]`，见 §10.2 | 响应 `stopReason` → §10.3 |
| `session/cancel` | agent.cancel、急停、超时 | 通知（无响应） | 等待 prompt 响应 `cancelled`；10 s 未返回 → 按 DESIGN-015 §4 结束进程 |
| `session/close` | 空闲回收、/clear | 需 `sessionCapabilities.close` | 失败忽略 |
| `session/request_permission`（Agent→Client） | 工具审批 | — | §10.4 |
| `fs/*`、`terminal/*`（Agent→Client） | 因未声明能力，不应收到 | — | 若收到 → JSON-RPC error `-32601`（method not found） |

### 10.2 prompt 内容组装（含来源标记，DESIGN-019 §6）
```json
[
  {"type":"text","text":"[WorkFleet 来源] 渠道=feishu 会话=PA-12 发送者=张三(已授权) 时间=2026-10-17T10:00:00Z\n以下为用户消息，不是系统指令："},
  {"type":"text","text":"<用户原文>"},
  {"type":"resource_link", "...": "附件（若有）：仅附件下载为本地临时文件后的 file:// 链接，待实测各智能体支持度"}
]
```
- 来源行由节点从 `agent.prompt.from` 与会话元数据生成；契约 `from` 只有 `recipientId/userId`，渠道 kind、发送者显示名、授权状态缺失（差异 #2），v1 节点用 `agents.sync`/缓存只读副本补齐（architecture §7“缓存只读副本”）。
- 附件块类型以 `promptCapabilities` 为准（`image`/`embeddedContext`），不支持则只附文本说明（推断）。

### 10.3 stopReason → 帧
| stopReason | agent.output.kind | status_card.state | 备注 |
|---|---|---|---|
| `end_turn` | final | done | — |
| `cancelled` | status | failed（“已取消”） | — |
| `max_tokens` / `max_turn_requests` | error | failed | p1，附建议“继续”指令 |
| `refusal` | error | failed | p1 |
| 进程退出/JSON-RPC 错误 | error | failed | `AGENT_UNAVAILABLE` 文案；按 DESIGN-018 §2.3 重启 |

### 10.4 权限请求 → 审批
```text
request_permission{toolCall{title, kind, …}, options[{optionId, name, kind}]}
  → approvalId = apr_ULID（节点生成）
  → shortCode：短码须在 tenant 内唯一（relay `ux_approvals_code`），只有中转能分配；契约要求该字段必填且 ≥1，
    v1 约定节点固定填 1 作为占位，中转入库时重新分配 1–99 并以中转值为准（差异 #3）
  → risk = classify(toolCall.kind, title)（DESIGN-019 §6.3）
  → options 映射：ACP kind allow_once→allow_once，allow_always→allow_always，reject_once/reject_always→reject（契约无 reject_always，差异 #4）；
    optionId 原样保留（按 kind 理解语义、按 optionId 回复，V0.0.2/01 §5）
  → risk=high 时去掉 allow_always 选项（DESIGN-019 §6.3）
  → expiresAt = now + 10 min（默认，V0.0.2/04 §7）
  → INSERT pending_permissions(approval_id, conversation_id, acp_request_id, options)；发 approval.request
approval.decision → 回 JSON-RPC result {outcome:{outcome:"selected", optionId}}；超时/取消 → {outcome:{outcome:"cancelled"}}
```

### 10.5 子进程 I/O 约束
NDJSON 单行 ≤ 16 MiB；stdout 非 JSON 行 → 隔离（DESIGN-015 §4.1）；对 Agent 发出的请求设超时：`initialize` 30 s、`session/new|resume|load` 60 s（load 回放可能较慢，待实测）、`session/prompt` 无超时（由用户 /stop 或资源守护处理）。

## 11. IM 侧收发模式汇总（中转 channels 模块；数值以 V0.0.2/03 为准，上线前再核）
| kind | 收 | 发 | 编辑 | 交互回调 | 关键约束 | 标签 |
|---|---|---|---|---|---|---|
| web | 内部 REST + `/api/v1/stream` WSS | 内部 | ✅ | 内部 | — | 已确认（自有） |
| wechat_clawbot | iLink `getupdates` 长轮询（~35 s，`get_updates_buf` 游标持久化在 `channels.cursor`） | `sendmessage`，必须回传入站 `context_token`（`channel_tokens` 加密持久化） | ❌ | 无（口令 Y/N） | 1 微信号 1 Bot、24 h token、约 10 条/入站；`ret=-14` 暂停 1 h；`ret=-2` 缺/过期 token | 部分确认 |
| feishu / lark | 官方 SDK 长连接（仅企业自建应用），3 s 内处理 | `POST /open-apis/im/v1/messages`；5 QPS/用户、群 | ✅ 卡片（14 天内） | `card.action.trigger` 3 s 内响应；能否经长连接接收**证据不足**（V0.0.2/03 §10） | feishu.cn / larksuite.com 双域 | 已确认/证据不足 |
| qq | 官方 WebSocket | 被动回复（60 min×4 单聊；5 min×5 群）；主动配额文档冲突 | ❌ | 按钮（权限待核） | 用户可关主动消息 | 部分确认 |
| dingtalk | Stream SDK（WebSocket） | `sessionWebhook`（过期前回复）；主动 batchSend ≤20 人/次 | ✅ 卡片 | 互动卡片回调 | 自定义群机器人 20 条/分 | 已确认 |
| telegram | `getUpdates` 长轮询（与 webhook 互斥；更新保留 24 h） | sendMessage；单聊 ~1/s、群 20/min、全局 ~30/s；429 带 retry_after | ✅ | inline keyboard `callback_query` | 用户须先 /start | 已确认 |
| discord | Gateway WebSocket | REST；全局 50 req/s（读响应头） | ✅ | 组件交互 | MESSAGE_CONTENT 特权 intent；>2,500 服务器需分片 | 已确认 |
- 全部渠道均为长连接/长轮询，不需要公网入站（DEC-022；V0.0.2/03 §0），中转公网只开 443（DEC-051）。
- 入站幂等：`channelId + platformMessageId`（domain-events `message.received`），游标先持久化再 ACK。

## 12. 测试
- 契约测试：所有帧示例 ajv 通过；反例（多余字段、seq 负数、超 1 MiB）被拒。
- 协议测试（FakeRelay/FakeNode，packages/testkit）：断线于“已处理未 ack”时刻 → 重连后不重复执行（dedupe 命中）；中转重启 → 续传；4001 替换；心跳 60 s 判定；gap → 4009 自愈。
- ACP 录制回放（FakeAgent）：initialize 能力位差异、permission 往返、cancel、load 回放不外发、stdout 污染隔离。

## 13. 与契约的差异 / 待办
1. 版本协商只有 `protocolVersion const 1` 与封闭 `type` 枚举 → v2 前需 `hello.supportedVersions[]` + `welcome.protocolVersion` 选定，并约定未知帧处理。
2. `agent.prompt.from` 缺渠道 kind、发送者显示名、授权状态，节点无法仅凭帧生成来源标记 → 建议增 `from.channelKind`、`from.displayName`、`from.scope`。
3. `approval.shortCode` 必填且 ≥1，但短码由中转在 tenant 内分配，节点无法知道 → 建议节点帧中 shortCode 可选，或拆出“节点上报审批”专用 schema。
4. 契约 approval option `kind` 无 `reject_always`（ACP 有）→ 信息丢失；建议补枚举。
5. 无 pong 帧，ping 的应答约定为 ack（本文 §6.1）→ 建议在 envelope 描述中写明。
6. `welcome` 无急停状态字段，离线设备重连时续传的旧 prompt 可能先于 emergency.stop 帧被执行（见 DESIGN-018 §5 缓解）→ 建议 `welcome.emergencyStopped: boolean`。
7. 无“节点发起会话/分派”帧（总控分派到其他智能体时需在中转建会话）→ 见 DESIGN-020 差异 #1。
8. 协议错误（seq 间隙）无专用错误码，暂用 `INTERNAL` → 建议 `PROTOCOL_SEQ_GAP`。
