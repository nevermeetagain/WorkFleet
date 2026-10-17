# TASK-010：中转 Web 渠道最小闭环：conversations/messages API、/api/v1/stream、agent.prompt/agent.output 转发

```yaml
id: TASK-010
slice: S0
status: todo
owner: Agent-Relay
tier: sonnect
size: 中
title: "中转 Web 渠道最小闭环：conversations/messages API、/api/v1/stream、agent.prompt/agent.output 转发"
dependsOn: ["006"]
blocks: ["012", "024", "025", "042"]
reqs: "REQ-F-015"
allowedPaths: ["apps/relay/src/modules/conversations/**", "apps/relay/src/modules/channels/infrastructure/adapters/web/**", "apps/relay/tests/**/conversations/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-010/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S0
- 来源需求：REQ-F-015（tasks.v1.json 原值 `REQ-F-015`）
- 来源方案：architecture §6.4（Web 是内置渠道 `web`，WSS 订阅 + REST 发送，与 IM 同账本）、§4.1（conversations）、ADR-005（经 node-gateway 发帧）、ADR-012（displayId、ID、时间）

## 2. 目标
Web 渠道最小闭环：会话的建/列、消息的写/读、`/api/v1/stream` 实时推送可用；Web 发送的消息经 `agent.prompt` 送达节点，节点回传的 `agent.output` 写入 append-only 账本并实时推到浏览器。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.1、§6.1（第 5、7 步）、§6.4、§7
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-015、REQ-F-019、REQ-NF-001/003
  - docs/WorkFleet-V0.0.4/00_governance/glossary.md（会话/代/消息）
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/conversations`（cursor/limit）、`POST /api/v1/conversations`（`{agentId}`，`Idempotency-Key`、`X-CSRF-Token`，201 Conversation）、`GET /api/v1/conversations/{conversationId}/messages`、`POST /api/v1/conversations/{conversationId}/messages`（`{text,replyToId?,attachmentIds?}`，202 Message；`DEVICE_OFFLINE`、`EMERGENCY_STOPPED`、`AGENT_UNAVAILABLE`；权限 `agent.prompt`）、`POST /api/v1/conversations/{conversationId}/clear`、`POST /api/v1/conversations/{conversationId}/cancel`、`GET /api/v1/stream`（101，`conversation.read`）
  - `packages/contracts/protocol/frames/agent.prompt.schema.json`（agentId、conversationId、generation、messageId、body、from.userId）、`agent.output.schema.json`（conversationId、generation、messageId、replyToId、kind final|status|error|digest、priority、body、nativeSessionId）、`agent.clear.schema.json`（newGeneration≥2）、`agent.cancel.schema.json`、`agent.status.schema.json`
  - `packages/contracts/schemas/entities/{conversation,message,message-body}.schema.json`（displayId `^[A-Z]{2,4}-\d{1,6}$`）
  - `packages/contracts/events/domain-events.json`：`message.received`（入站持久化后）
  - 表：`conversations`（`ux_conversations_active`、`ux_conversations_display`）、`display_id_counters`、`messages`（`ux_messages_idem`、`messages_fts` 触发器、append-only 触发器）、`tenants.emergency_stopped_at`、`agents`
- 前置任务：TASK-006
- 前置状态：TASK-006 已合并（`node-gateway.sendToNode`/`onNodeFrame`、设备在线状态、`WF_RELAY_DEV_SEED_ECHO` 回声智能体）

## 4. 输出
- `apps/relay/src/modules/conversations/{domain,application,interfaces/http,interfaces/ws,infrastructure}/**`、`index.ts`（公开 `appendMessage()`、`getConversation()`、`findByDisplayId()`、`findByNativeSessionId()`、`listMessages()`、`sendPrompt()`；扩展点 `registerInboundInterceptor()`（TASK-024 挂指令解析）与 `registerPromptGuard()`（发送 `agent.prompt` 前调用，可返回 hold，供 TASK-028 实现 held））
- 占位文件（供 TASK-025 在其 allowedPaths 内填充，避免其改本模块路由）：`conversations/application/history/index.ts`（空导出）、`conversations/interfaces/http/history.routes.ts`（空插件，由本模块路由聚合器加载）
- `apps/relay/src/modules/channels/infrastructure/adapters/web/**`（Web 渠道：把会话事件推给 `/api/v1/stream` 订阅者；按用户/组织过滤）
- 测试：`apps/relay/tests/unit/modules/conversations/**`、`apps/relay/tests/integration/modules/conversations/**`

## 5. Execution Steps
1. [ ] 领域：Conversation（generation、displayId、state）、Message（append-only，`plain_text` 由 IR 块拼接用于 FTS）；displayId 生成：前缀取智能体 alias 中的字母转大写截前 4 位，不足 2 位用 `WF`，序号来自 `display_id_counters`（DESIGN-004 缺失，此规则为本卡假设，已登记）。
2. [ ] `POST /conversations`：校验 agent 属于本组织；同一 `(agent, route=null, recipient=null)` 已有 active 会话则返回该会话（受 `ux_conversations_active` 约束）；否则新建 generation=1。
3. [ ] `POST /messages`：若 `tenants.emergency_stopped_at` 非空→423 `EMERGENCY_STOPPED`；文本以 `/` 或 `／` 开头且存在已注册的入站拦截器→交拦截器处理（TASK-024），否则作为普通文本；写入 `messages`（direction inbound、author user、idempotencyKey=`web:<principal>:<Idempotency-Key>`），发 `message.received`。
4. [ ] 转发：组装 `agent.prompt{agentId,conversationId,generation,messageId,body,from.userId}` 调 `sendToNode(agent.deviceId, …)`；设备离线时帧仍入 `node_outbox` 排队，并返回 409 `DEVICE_OFFLINE`（`details.messageId`、`details.queued=true`）；智能体 `status=unavailable`→409 `AGENT_UNAVAILABLE`。
5. [ ] 回传：`onNodeFrame('agent.output')` → 以 `frame.messageId` 为消息 id、`node:<messageId>` 为幂等键追加 outbound 消息（重复帧不重复入账）；有 `nativeSessionId` 时更新会话；`agent.status` 更新 `agents.status`。
6. [ ] `/clear`：generation+1、旧记录保留，发 `agent.clear{newGeneration}`；`/cancel`：发 `agent.cancel`；二者均写 system 消息。
7. [ ] `/api/v1/stream`：会话 Cookie 鉴权的 WebSocket；推送事件 `{type:'message.created'|'conversation.updated'|'agent.status', data}`（契约缺事件 schema，事件体直接复用 message/conversation 实体 schema，已登记缺陷）；仅推送本组织且有 `conversation.read` 的会话。
8. [ ] 写测试：会话创建幂等；消息入账与 FTS 可检索；离线返回 `DEVICE_OFFLINE` 且 `node_outbox` 有帧；`agent.output` 重复投递只入账一次；`/clear` 后 generation=2 且旧消息仍可分页查到；stream 只收到本组织事件。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：集成测试：登录→`POST /conversations{agentId}`→201；`POST /messages{text:"hello"}`→202，`node_outbox` 出现一条 `type=agent.prompt` 帧且 payload 通过 `agent.prompt.schema.json`。
- [ ] AC-2：模拟节点回 `agent.output{kind:final}`：`GET /messages` 返回 inbound+outbound 两条；同一帧重复两次仍只有 1 条 outbound（`ux_messages_idem`）（REQ-NF-003）。
- [ ] AC-3：设备离线时 `POST /messages`→409 `DEVICE_OFFLINE` 且消息已入账、帧已排队；`tenants.emergency_stopped_at` 非空时→423 `EMERGENCY_STOPPED`。
- [ ] AC-4：`POST /clear`→会话 generation=2，`node_outbox` 有 `agent.clear{newGeneration:2}`，generation=1 的消息仍可查询（REQ-F-019）。
- [ ] AC-5：`/api/v1/stream` 订阅者在 `agent.output` 落库后收到 `message.created`；另一组织用户的订阅收不到（REQ-F-002）。
- [ ] AC-6：所有新会话 `displayId` 匹配 `^[A-Z]{2,4}-\d{1,6}$` 且组织内唯一。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/relay test tests/unit/modules/conversations tests/integration/modules/conversations
pnpm -F @workfleet/relay typecheck
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-010/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/relay/src/modules/conversations/**`
- `apps/relay/src/modules/channels/infrastructure/adapters/web/**`
- `apps/relay/tests/**/conversations/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-010/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-010/` 除外）
- `apps/relay/src/modules/conversations/application/history/**` 与 `interfaces/http/history*` 中除上述占位文件外的实现（归 TASK-025）
- `apps/relay/src/modules/channels/**` 中除 `infrastructure/adapters/web/**` 外的路径（TASK-042）
- `apps/relay/src/modules/{commands,devices,node-gateway,identity,tenancy}/**`
- `apps/web/**`、`apps/node/**`

## 11. 依赖与阻塞
- Depends on：TASK-006
- Blocks：TASK-012, TASK-024, TASK-025, TASK-042
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - `GET /api/v1/stream` 事件类型、`GET /api/v1/conversations` 的 projectId/agentId 过滤参数在契约中缺失 → 本卡按上述假设实现并登记，若主 Agent 要求先补契约则 blocked
  - Web 渠道适配器先于 TASK-042 的 ChannelAdapter 端口落地，而 TASK-042 不得改 `adapters/web/**` → 端口不兼容时需另立任务迁移，本卡不预判
  - `DEVICE_OFFLINE` 契约语义为“已入队”却以 409 返回（非 202）→ 按契约实现，前端需特殊处理，已登记
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：在既有 node-gateway 之上做 CRUD + 转发，路径清晰，sonnect 足够；可靠性由幂等键与测试兜底。

## 13. 升级条件
- 需要改变会话唯一性规则（`ux_conversations_active` 使同组织多用户共享同一 Web 会话）→ 升 opus 评审数据模型并 blocked
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 风险：`ux_conversations_active` 使同一智能体在 Web 渠道（route/recipient 皆空）只有一个 active 会话，组织内多用户共用——数据模型限制，已报告。
- 假设：displayId 前缀规则为本卡假设（DESIGN-004 文档缺失）。
- 假设（NON_BLOCKING，U-04）：跨境 p95 时延（REQ-NF-001 ≤2 s）由 TASK-210 测量，本卡不做性能优化。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-010/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
