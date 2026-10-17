# TASK-028：审批与 held（中转侧）：approval.request→待审批→decision→回节点；超时拒绝；held 队列

```yaml
id: TASK-028
slice: S1
status: todo
owner: Agent-Relay
tier: opus
size: 中
title: "审批与 held（中转侧）：approval.request→待审批→decision→回节点；超时拒绝；held 队列"
dependsOn: ["024", "026"]
blocks: ["029", "030", "047"]
reqs: "REQ-F-020"
allowedPaths: ["apps/relay/src/modules/approvals/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-028/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S1
- 来源需求：REQ-F-020（tasks.v1.json 原值 `REQ-F-020`）
- 来源方案：REQ-F-020（按钮或 Y{n}/N{n} 审批；超时默认拒绝；待审批期间新消息进入 held，审批后按序投递）、architecture §4.1（approvals）/§6.1 第 4 步、glossary（审批、暂存 held）、DEC-011/012

## 2. 目标
中转完整处理审批生命周期：接收 `approval.request` → 落库并分配组织内短码 → 推送待审批 → `POST /approvals/{id}/decide` 或超时拒绝 → 发 `approval.decision` 回节点；待审批期间发往该智能体的新消息进入 held，决策后按序放行。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-020
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.1、§6.1
  - docs/WorkFleet-V0.0.4/00_governance/glossary.md
- 契约：
  - `packages/contracts/protocol/frames/approval.request.schema.json`（node→relay，`approval`）、`approval.decision.schema.json`（relay→node：approvalId、optionId、decidedBy）
  - `packages/contracts/schemas/entities/approval.schema.json`（shortCode 1–99、kind、risk low|medium|high、options、status pending|approved|rejected|expired|cancelled、decidedBy userId|recipientId|null、expiresAt）
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/approvals`（conversation.read）、`POST /api/v1/approvals/{approvalId}/decide`（`{optionId}`，Idempotency-Key，approval.decide_low；high 风险需 approval.decide_high 或设备所有者；`APPROVAL_EXPIRED`、`APPROVAL_ALREADY_DECIDED`、`FORBIDDEN`）
  - `packages/contracts/identity/permissions.json` extraRules（`approval.decide_high` 允许 `principal.userId == device.ownerUserId`）；`events/domain-events.json`：`approval.requested`、`approval.decided`、`message.held`
  - 表：`approvals`（`ux_approvals_code(tenant_id, short_code) WHERE status='pending'`、`ix_approvals_pending`）、`held_messages`、`messages`（审批卡片以 `approval` IR 块写入 system 消息）
- 前置任务：TASK-024、TASK-026
- 前置状态：TASK-024（指令注册表）与 TASK-026（智能体登记）已合并；TASK-010 提供 `registerPromptGuard()` 与 `sendPrompt()`

## 4. 输出
- `apps/relay/src/modules/approvals/{domain,application,interfaces/http,interfaces/node,infrastructure}/**`、`index.ts`（公开 `requestApproval()`、`decide(approvalId, optionId, principal)`、`findPendingByShortCode(tenantId, n)`、`isHeld(agentId)`；为 TASK-047 预留 `application/text-codes/` 目录但不写入）
- 超时工作者 `application/expire-worker.ts`（每 5 s 扫描 `ix_approvals_pending`）
- 测试：`apps/relay/tests/unit/modules/approvals/**`、`apps/relay/tests/integration/modules/approvals/**`

## 5. Execution Steps
1. [ ] `approval.request` 处理：校验 agent/会话属于该设备组织；按 approval.id 幂等落库；忽略节点给的 shortCode，重新分配本组织 pending 中最小空闲的 1–99（99 个全占→该审批直接 `status=rejected` 并回 `approval.decision` 拒绝，记 p0 日志）；发 `approval.requested`。
2. [ ] 在会话写一条 system 消息（body 含 `{type:'approval', approvalId}` 块与 summary），经 TASK-010 的 stream 推给 Web；IM 渲染与投递由 TASK-045/047 负责。
3. [ ] held：经 `conversations.registerPromptGuard` 注册守卫——目标智能体存在 pending 审批时，消息写 `held_messages` 并发 `message.held`，不发 `agent.prompt`。
4. [ ] `POST /decide`：status 非 pending→409 `APPROVAL_ALREADY_DECIDED`；已过期→409 `APPROVAL_EXPIRED`；risk=high 且无 `approval.decide_high` 且非设备所有者→403 `FORBIDDEN`；optionId 不在 options 中→400 `VALIDATION_FAILED`；成功→更新 status（allow_*→approved，reject→rejected）、decided_by、decided_at，发 `approval.decision{approvalId,optionId,decidedBy:userId}`，发 `approval.decided`。
5. [ ] 超时：`expires_at` 过期且仍 pending→status=expired，选 options 中 kind=reject 的 optionId 发 `approval.decision{decidedBy:'system'}`（超时默认拒绝）。
6. [ ] 放行：任一决策（含超时）后，该智能体若再无 pending 审批，按 `held_at` 升序逐条 `sendPrompt` 并写 `released_at`。
7. [ ] `GET /approvals`：本组织审批分页，pending 优先、按 created_at 倒序；遵守 projectScope。
8. [ ] 测试：短码分配与复用；重复 request 幂等；决策四类错误码；high 风险设备所有者可批；超时拒绝；held 3 条消息在批准后按序发出。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：集成测试：节点发 `approval.request` → `GET /approvals` 出现 pending 项且 shortCode ∈ [1,99]、组织内 pending 唯一；同一 approval.id 重发不产生第二条。
- [ ] AC-2：`POST /approvals/{id}/decide{optionId:allow_once}` → 200，`node_outbox` 出现通过 schema 的 `approval.decision` 帧；再次决策→409 `APPROVAL_ALREADY_DECIDED`。
- [ ] AC-3：过期后决策→409 `APPROVAL_EXPIRED`；假时钟越过 expiresAt → 自动 `status=expired` 并发出 reject 选项的 `approval.decision`（超时默认拒绝，REQ-F-020）。
- [ ] AC-4：risk=high：operator（非设备所有者）→403 `FORBIDDEN`；设备所有者 operator → 200（extraRules）。
- [ ] AC-5：pending 期间发送 3 条消息 → `held_messages` 3 行且无 `agent.prompt` 帧；批准后 3 条 `agent.prompt` 按发送顺序进入 `node_outbox`，`released_at` 全部非空。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/relay test tests/unit/modules/approvals tests/integration/modules/approvals
pnpm -F @workfleet/relay typecheck
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-028/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/relay/src/modules/approvals/**`
- 明确写出的测试目录（本模块专属；allowedPaths 未含测试路径，按任务指令 §3 在此显式声明，执行前须经主 Agent 确认）：
  - `apps/relay/tests/unit/modules/approvals/**（不含 text-codes 子目录）`
  - `apps/relay/tests/integration/modules/approvals/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-028/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-028/` 除外）
- `apps/relay/src/modules/approvals/application/text-codes/**`（TASK-047）
- `apps/relay/src/modules/{conversations,commands,routing,delivery,node-gateway}/**`
- `apps/web/**`、`apps/node/**`

## 11. 依赖与阻塞
- Depends on：TASK-024, TASK-026
- Blocks：TASK-029, TASK-030, TASK-047
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - TASK-010 未提供 `registerPromptGuard` → held 无法在不改 conversations 的前提下实现 → blocked 提单 TASK-010
  - `approval.request` 帧强制携带 shortCode/expiresAt/status 等由中转决定的字段，节点值与中转值冲突时以中转为准——若评审要求节点值权威则需改契约（blocked）
  - IM 入站消息的 held（经 routing）需 TASK-044 调用本模块 `isHeld()`，本卡不改 routing
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
opus　理由：审批是安全决策点（含高风险操作授权与超时默认拒绝），且 held 顺序涉及可靠性，按 opus 执行（cost-budget S1 计 opus 券）。

## 13. 升级条件
- 本卡已为 opus：需改变“超时默认拒绝”或 extraRules 语义 → 升 fable 并 blocked
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：短码耗尽（>99 个 pending）直接拒绝为本卡假设，DESIGN-005 缺失，待评审。
- 风险：节点离线时 `approval.decision` 排队于 `node_outbox`，节点重连后可能已超时（节点侧需幂等处理）。
- 本卡不涉及 U-02…U-08。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-028/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
