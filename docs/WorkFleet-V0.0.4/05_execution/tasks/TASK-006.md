# TASK-006：devices：配对码、claim、node-gateway WSS（hello/welcome/ack/ping、outbox 续传、去重）

```yaml
id: TASK-006
slice: S0
status: todo
owner: Agent-Relay
tier: opus
size: 大
title: "devices：配对码、claim、node-gateway WSS（hello/welcome/ack/ping、outbox 续传、去重）"
dependsOn: ["005"]
blocks: ["010", "026"]
reqs: "REQ-F-001/002"
allowedPaths: ["apps/relay/src/modules/devices/**", "apps/relay/src/modules/node-gateway/**", "apps/relay/tests/**/devices/**", "apps/relay/tests/**/node-gateway/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-006/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S0
- 来源需求：REQ-F-001、REQ-F-002（tasks.v1.json 原值 `REQ-F-001/002`）
- 来源方案：ADR-005（WSS + envelope + 每方向单调 seq + 累积 ack + 断线续传；心跳 20 s、60 s 判断线、帧 ≤1 MiB）、ADR-006（配对码换设备令牌，256-bit 随机，库内只存 SHA-256）、architecture §4.1（devices、node-gateway）

## 2. 目标
控制台可生成 8 位配对码，节点用 `POST /api/v1/devices/claim` 换取设备令牌并经 `GET /api/v1/node-gateway` 建立 WSS；握手 `hello/welcome`、累积 `ack`、`ping` 心跳、`node_outbox` 断线续传与 `node_inbox_dedupe` 去重全部可用，设备在线状态正确。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-005-中转↔节点协议.md、ADR-006-鉴权与权限.md
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.1、§6.1 第 5 步（离线排队）
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-001/002、REQ-NF-003
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`POST /api/v1/devices/pairing-codes`（201 `{code:^[0-9A-Z]{8}$, expiresAt}`，`device.pair`，10 分钟）、`POST /api/v1/devices/claim`（201 `{device, deviceToken, wsUrl}`；`PAIRING_CODE_INVALID`、`RATE_LIMITED`）、`GET /api/v1/devices`（`device.read`）、`POST /api/v1/devices/{deviceId}/revoke`、`POST /api/v1/devices/{deviceId}/rotate-token`（`device.revoke`）、`GET /api/v1/node-gateway`（101，`x-auth: device`，`Authorization: Bearer`）
  - `packages/contracts/protocol/envelope.schema.json`（`v=1`、`seq`、`type`、`idempotencyKey`、`traceId`、`sentAt`、`payload`；hello/welcome/ack/ping 的 seq=0）
  - `packages/contracts/protocol/frames/hello.schema.json`（protocolVersion=1、nodeVersion、os、lastAckedRelaySeq、agents）、`welcome.schema.json`（deviceId、lastAckedNodeSeq、serverTime、heartbeatSec=20）、`ack.schema.json`（upToSeq）、`ping.schema.json`、`error.schema.json`（code、message、refSeq）
  - `packages/contracts/schemas/entities/device.schema.json`、`identity/device-token-claims.schema.json`；错误码 `PAIRING_CODE_INVALID`、`DEVICE_REVOKED`、`PROTOCOL_VERSION_UNSUPPORTED`、`PAYLOAD_TOO_LARGE`、`UNAUTHENTICATED`
  - `packages/contracts/events/domain-events.json`：`device.online`（hello 握手成功）、`device.offline`（60 s 无帧）
  - 表：`pairing_codes`、`devices`（`token_hash`、`prev_token_hash`、`last_acked_node_seq`、`relay_seq`、`revoked_at`）、`node_outbox`、`node_inbox_dedupe`、`agents`（开发种子）
- 前置任务：TASK-005
- 前置状态：TASK-005 已合并（会话、CSRF、权限拦截器、默认项目）

## 4. 输出
- `apps/relay/src/modules/devices/**`（配对码、claim、列表、吊销、轮换、在线状态；`index.ts` 公开 `resolveDevice()`、`isOnline()`）
- `apps/relay/src/modules/node-gateway/**`（WSS 升级、令牌鉴权、envelope 校验、seq/ack、outbox 续传、去重、心跳、背压；`index.ts` 公开 `sendToNode(deviceId, type, payload)`、`onNodeFrame(type, handler)`）
- 开发/测试种子：`WF_RELAY_DEV_SEED_ECHO=1` 时，claim 成功后为该设备在默认项目下建一条 `agents` 行（alias `echo`、adapterId `fake-echo`、kind `acp`、writeMode `read_only`），供 S0 步行骨架使用
- 测试：`apps/relay/tests/unit/modules/devices/**`、`apps/relay/tests/unit/modules/node-gateway/**`、`apps/relay/tests/integration/modules/node-gateway/**`（使用 `ws` 客户端模拟节点；TASK-008 合并后可改用 FakeRelay 的对偶工具）

## 5. Execution Steps
1. [ ] 配对码：Crockford 风格 `[0-9A-Z]{8}`，写 `pairing_codes`（10 分钟过期，一次性）；claim 校验未过期未使用，否则 400 `PAIRING_CODE_INVALID`；claim 端点按 IP 限速→`RATE_LIMITED`。
2. [ ] claim 成功：建 `devices`（ownerUserId=配对码创建者），生成 256-bit 令牌，库内存 SHA-256；返回 `wsUrl` = `WF_RELAY_PUBLIC_URL` 换 `wss://` + `/api/v1/node-gateway`。
3. [ ] WSS 升级：校验 `Authorization: Bearer`→设备；吊销设备→握手拒绝 `DEVICE_REVOKED`；轮换期内 `prev_token_hash` 仍可连一次并在连接后作废。
4. [ ] 握手：首帧必须为 `hello`（protocolVersion≠1→发 `error{code:PROTOCOL_VERSION_UNSUPPORTED}` 后关闭）；回 `welcome{deviceId,lastAckedNodeSeq,serverTime,heartbeatSec:20}`；按 `hello.lastAckedRelaySeq` 从 `node_outbox` 重放 seq 更大的未确认帧；发 `device.online`。
5. [ ] 收发：出站帧 seq 取 `devices.relay_seq+1` 并写 `node_outbox`（先落库后发送）；收 `ack.upToSeq` 标记 `acked_at`；入站非控制帧按 `(device_id, idempotencyKey)` 写 `node_inbox_dedupe` 去重后分发给 `onNodeFrame` 订阅者，并累积回 `ack`。
6. [ ] 心跳与断线：每 20 s 发 `ping`；60 s 无任何帧判定断线，更新 `last_seen_at`、发 `device.offline`；单帧 >1 MiB→`error{code:PAYLOAD_TOO_LARGE}`；发送缓冲超阈值暂停读取 outbox（背压）。
7. [ ] 吊销/轮换端点：吊销立即断开现有连接并置 `revoked_at`（`device.revoke` 或设备所有者 extraRule）。
8. [ ] 开发种子（见“输出”），仅在环境变量开启时生效，生产默认关闭。
9. [ ] 写测试：配对码过期/重复使用；握手成功/版本过旧；断线重连后续传且不重复（相同 idempotencyKey 只分发一次）；60 s 无帧离线（用假时钟）；吊销后重连被拒。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`POST /devices/pairing-codes`（admin/operator 会话）→201 且 code 匹配 `^[0-9A-Z]{8}$`；过期或二次使用的 code 调 `POST /devices/claim`→400 `PAIRING_CODE_INVALID`。
- [ ] AC-2：模拟节点 `hello{protocolVersion:1,lastAckedRelaySeq:0}`→收到 `welcome{heartbeatSec:20}`，设备 `status=online`；`protocolVersion` 非 1→收到 `error{code:"PROTOCOL_VERSION_UNSUPPORTED"}` 且连接关闭。
- [ ] AC-3：中转在节点断线期间 `sendToNode` 3 帧，节点以 `lastAckedRelaySeq=k` 重连后按序收到 seq>k 的全部帧、无缺无重；节点重发同一 `idempotencyKey` 帧，订阅者只被调用 1 次（`node_inbox_dedupe` 1 行）（REQ-NF-003）。
- [ ] AC-4：假时钟推进 60 s 无帧→设备 `status=offline` 且发出 `device.offline` 事件。
- [ ] AC-5：吊销后该令牌握手被拒（`DEVICE_REVOKED`）；`devices.token_hash` 为 64 位十六进制，库中无明文令牌。
- [ ] AC-6：所有帧经 `@workfleet/contracts` 的 `validateEnvelope()` 校验，非法帧回 `error` 帧（带 `refSeq`）且不进入分发。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/relay test tests/unit/modules/devices tests/unit/modules/node-gateway
pnpm -F @workfleet/relay test tests/integration/modules/node-gateway
pnpm -F @workfleet/relay typecheck
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-006/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/relay/src/modules/devices/**`
- `apps/relay/src/modules/node-gateway/**`
- `apps/relay/tests/**/devices/**`
- `apps/relay/tests/**/node-gateway/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-006/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-006/` 除外）
- `apps/relay/src/modules/agents-registry/**`（TASK-026；本卡的种子仅经 devices 仓储写 agents 行，不建 agents-registry 模块）
- `apps/relay/src/modules/conversations/**`（TASK-010）
- `apps/relay/src/modules/{identity,tenancy}/**`、`apps/relay/src/core/**`
- `apps/node/**`

## 11. 依赖与阻塞
- Depends on：TASK-005
- Blocks：TASK-010, TASK-026
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 主 Agent 不同意开发种子回声智能体（S0 无其他途径产生 agents 行：智能体登记 API 在 TASK-026、项目模块在 TASK-061）→ TASK-010/013 无法闭环 → blocked 等裁定
  - `welcome` 帧不含 tenantId/projectId，节点无法自建合法 agent（agent.schema 要求 projectId）→ 本卡不尝试从 `hello.agents` 落库（留给 TASK-026 的 `agents.sync`）
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
opus　理由：协议续传/去重与设备令牌属可靠性与安全核心，错误会导致丢消息或越权，按 opus 执行。

## 13. 升级条件
- 本卡已为 opus：需改 envelope/帧语义（如 welcome 增加字段）→ 升 fable 并 blocked
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
大　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-04 相关）：跨境链路断线频繁，以 60 s 判定断线 + 续传应对；实际 RTT/失败率由 TASK-041 记录。
- 风险：`node_outbox` 无清理策略（已 ack 帧何时删除未规定）→ 本卡保留 7 天并在完成记录登记，待 DESIGN-016（文档缺失）确认。
- 风险：开发种子若误在生产开启会产生无主智能体 → 生产配置拒绝该变量（config 校验）。
- 本卡不涉及 U-02、U-05…U-07。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-006/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
