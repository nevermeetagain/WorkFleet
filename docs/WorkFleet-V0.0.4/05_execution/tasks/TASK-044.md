# TASK-044：routing 内核：管理模式、/use 焦点、@别名、引用回复溯源、dry-run

```yaml
id: TASK-044
slice: S2
status: todo
owner: Agent-Relay
tier: opus
size: 大
title: "routing 内核：管理模式、/use 焦点、@别名、引用回复溯源、dry-run"
dependsOn: ["043", "024"]
blocks: ["046", "047", "062", "102"]
reqs: "REQ-F-016/017"
allowedPaths: ["apps/relay/src/modules/routing/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-044/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S2
- 来源需求：REQ-F-016、REQ-F-017（tasks.v1.json 原值 `REQ-F-016/017`）
- 来源方案：REQ-F-016/017、DEC-005（MUST NOT 由 LLM 决定发往哪个渠道）、G2（引用回复溯源）、architecture §4.1（routing：绑定表、确定性选路、回复溯源、dry-run）/§6.1 第 3–7 步、DESIGN-006 逻辑（文档未落地）

## 2. 目标
routing 内核在管理模式下确定性地把已授权接收人的入站消息送到唯一目标智能体（引用回复 > `@别名` > `/use` 焦点 > 绑定默认来源），把智能体输出回投给该接收人，提供绑定 CRUD 与 dry-run 预览。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-016、REQ-F-017、§5 第 2 条
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.1、§6.1
  - docs/WorkFleet-V0.0.4/00_governance/glossary.md（绑定、模式、焦点、会话）
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/routes`（route.read）、`POST /api/v1/routes`（route.write；`ROUTE_INVALID`）、`PATCH /api/v1/routes/{routeId}`（`ROUTE_INVALID`、`CONFLICT`）、`DELETE /api/v1/routes/{routeId}`、`POST /api/v1/routes/dry-run`（route.dry_run；请求 `{recipientId, text, replyToMessageId?}`，响应 `{targetAgentId, reason, held, outboundPreview[]}`）
  - `packages/contracts/schemas/entities/route.schema.json`（mode management|notification|team|supervisor、sources、targets、defaultSourceId、filterRuleIds、priorityFloor、enabled）、`conversation.schema.json`、`message.schema.json`（replyToId、platformMessageId）
  - `packages/contracts/commands/im-commands.json`（`/use <alias>`、`@alias <text>`、`/list`、`/clear`、`/stop`、`/status` 在 IM 渠道的执行）、`events/domain-events.json`：`message.routed`、`route.updated`
  - `packages/contracts/errors/error-codes.json`：`ROUTE_INVALID`（422）、`DEVICE_OFFLINE`（会话内提示“设备离线，已排队”）、`AGENT_UNAVAILABLE`
  - 表：`routes`、`route_sources`、`route_targets`（`ix_route_targets_recipient`）、`recipient_focus`、`conversations`（`ux_conversations_active(agent, route, recipient)`）、`messages`（`ux_messages_platform(channel_id, platform_message_id)` 用于溯源）
- 前置任务：TASK-043、TASK-024
- 前置状态：TASK-043（`gateInbound`、`linkedPrincipal`）与 TASK-024（`parse`、`registerCommand`、`executeCommand`）已合并；依赖 TASK-010 的 conversations 公开 API 与 `sendPrompt`（内含 TASK-028 的 held 守卫）、TASK-045 的 `delivery.enqueue`（并行开发时以端口桩替代）

## 4. 输出
- `apps/relay/src/modules/routing/domain/{resolve-target.ts,route-rules.ts}`（纯函数选路，输出 `{targetAgentId, reason}`；reason ∈ quote_reply|at_alias|focus|route_default|none）
- `apps/relay/src/modules/routing/application/{route-inbound.ts,route-outbound.ts,dry-run.ts,crud/**,im-commands/**}`（IM 渠道的 `/use` 焦点执行器等经 `commands.registerCommand` 注册）
- `apps/relay/src/modules/routing/interfaces/http/**`、`infrastructure/**`、`index.ts`（公开 `route(inbound)`、`dryRun()`；为 TASK-062/102 预留 `application/device-select/`、`application/modes/` 目录但不写入）
- 测试：`apps/relay/tests/unit/modules/routing/**`、`apps/relay/tests/integration/modules/routing/**`

## 5. Execution Steps
1. [ ] 绑定 CRUD：本卡只接受 `mode=management`（多来源→一个接收人或多个本人接收人）；其余模式→422 `ROUTE_INVALID`（`details.reason=mode_not_supported_yet`，由 TASK-102 开启）；sources/targets 必须同组织、同项目范围；version 乐观锁→`CONFLICT`；变更发 `route.updated`。
2. [ ] 入站管线：`channels.onInbound` → `recipients.gateInbound`（未授权已在此终止）→ `commands.parse`：指令交 `executeCommand`（以 `linkedPrincipal` 判权）；普通文本进入选路。
3. [ ] 确定性选路（`resolve-target.ts`，禁止任何模型参与）：① 引用回复：`quoteOfPlatformMessageId` → `messages(channel_id, platform_message_id)` → 其会话智能体（G2）；② 文本以 `@alias ` 开头 → 该别名（剥离前缀）；③ `recipient_focus` → 焦点智能体；④ 包含该接收人的 management 绑定的 `defaultSourceId`；⑤ 都无 → 回提示“请先 /use 选择智能体”并附 `/list` 结果。
4. [ ] 会话：按 `(agent, route, recipient)` 取 active 会话，无则创建；入站消息以 `channel:<channelId>:<platformMessageId>` 为幂等键入账；调用 `conversations.sendPrompt`（held 由 TASK-028 守卫处理）；设备离线→回“设备离线，已排队”；发 `message.routed`。
5. [ ] IM 指令执行器：`/use <alias>` 写 `recipient_focus`；`/list`、`/status`、`/clear`、`/stop` 在 IM 中复用 TASK-024 的逻辑并以文本回发。
6. [ ] 出站：订阅 conversations 的出站消息（有 recipientId 的会话）→ 过滤（TASK-142 前直通，预留 `filterOutbound` 调用点）→ 消息 tags 加 `[项目/alias]` → `delivery.enqueue(messageId, [recipientId])`。
7. [ ] dry-run：用与真实选路相同的纯函数计算 `targetAgentId/reason/held`（held 来自 `approvals.isHeld`），`outboundPreview` 给出该接收人将看到的渲染预览（经 delivery 渲染器，过滤直通）；不写任何数据。
8. [ ] 表驱动测试：选路优先级 5 条分支 + 冲突组合（引用回复与 @别名同时出现时引用优先）；同一输入多次运行结果一致；dry-run 与真实路由结果一致；非 management 模式 422。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：选路表驱动测试覆盖 quote_reply / at_alias / focus / route_default / none 五种 reason 及组合优先级，全部通过且结果确定（重复 100 次一致）。
- [ ] AC-2：集成测试（测试替身渠道）：已授权接收人 `@z1 你好` → 只有 z1 会话收到 `agent.prompt`；`/use cc1` 后普通文本 → cc1；引用 z1 的某条回复再回复 → 回到 z1 会话（REQ-F-017）。
- [ ] AC-3：智能体 `agent.output` 落库后 `delivery.enqueue` 被调用一次，目标为该会话 recipientId（REQ-F-016 管理模式多对一）。
- [ ] AC-4：`POST /api/v1/routes/dry-run` 返回的 `targetAgentId/reason` 与对同一输入真实路由的结果一致，且调用前后数据库无写入。
- [ ] AC-5：`POST /api/v1/routes`（body `mode: notification`）→ 422 `ROUTE_INVALID`；跨组织 recipient/agent → 404 `NOT_FOUND`。
- [ ] AC-6：routing 源码不 import 任何模型/LLM 客户端（依赖守卫或 grep 断言，DEC-005）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/relay test tests/unit/modules/routing tests/integration/modules/routing
pnpm -F @workfleet/relay typecheck
! grep -rniE "openai|anthropic|llm|model-profile" apps/relay/src/modules/routing
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-044/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/relay/src/modules/routing/**`
- 明确写出的测试目录（本模块专属；allowedPaths 未含测试路径，按任务指令 §3 在此显式声明，执行前须经主 Agent 确认）：
  - `apps/relay/tests/unit/modules/routing/**（不含 device-select、modes 子目录）`
  - `apps/relay/tests/integration/modules/routing/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-044/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-044/` 除外）
- `apps/relay/src/modules/routing/application/{device-select,modes}/**`（TASK-062/102）
- `apps/relay/src/modules/{conversations,commands,recipients,approvals,delivery,channels,permissions-filter}/**`（仅经 index 公开 API）
- `apps/web/**`、`apps/node/**`

## 11. 依赖与阻塞
- Depends on：TASK-043, TASK-024
- Blocks：TASK-046, TASK-047, TASK-062, TASK-102
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - TASK-010 的 conversations 未公开“按 (agent, route, recipient) 打开会话”的 API → blocked 提单 TASK-010
  - TASK-042 的入站事件不含引用的平台消息 id（`quoteOfPlatformMessageId`）→ 引用溯源无法实现 → blocked 提单 TASK-042
  - `delivery.enqueue`（TASK-045）未合并时以端口桩开发；接口不一致时 blocked
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
opus　理由：路由内核是确定性选路与回复溯源的唯一事实点，错误会把消息发给错误的智能体或人，且 S5 的模式扩展都建立在其上，按 opus 执行。

## 13. 升级条件
- 本卡已为 opus：若需引入非确定性选路或改变 MUST NOT（DEC-005）→ 升 fable 并 blocked
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
大　是否小于 2 小时：否

## 15. 风险与假设
- 假设：选路优先级（引用 > @别名 > 焦点 > 绑定默认）为本卡设计假设，DESIGN-006 文档缺失，需评审确认。
- 假设（NON_BLOCKING，U-02）：微信引用回复字段待真机确认（TASK-041 `quoteReply=false`）→ 微信上 REQ-F-017 暂以 @别名/焦点兜底。
- 风险：`ux_conversations_active` 以 (agent, route, recipient) 唯一，管理模式下 route 变更会产生新会话，旧会话需关闭策略（待 DESIGN-004）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-044/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
