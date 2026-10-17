# TASK-047：IM 审批口令 Y{n}/N{n} 与无按钮渠道渲染

```yaml
id: TASK-047
slice: S2
status: todo
owner: Agent-Relay
tier: sonnect
size: 小
title: "IM 审批口令 Y{n}/N{n} 与无按钮渠道渲染"
dependsOn: ["028", "044"]
blocks: ["048"]
reqs: "REQ-F-020"
allowedPaths: ["apps/relay/src/modules/approvals/application/text-codes/**", "apps/relay/src/modules/commands/application/approval-codes/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-047/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S2
- 来源需求：REQ-F-020（tasks.v1.json 原值 `REQ-F-020`）
- 来源方案：REQ-F-020（IM 以按钮或 `Y{n}/N{n}` 审批）、im-commands.json（`Y{n} / N{n}`：批准/拒绝第 n 号审批，approval.decide_low）、DEC-024（无按钮渠道按能力降级）

## 2. 目标
IM 用户回复 `Y{n}`/`N{n}` 即可批准/拒绝第 n 号待审批（权限与风险规则同 Web），无按钮渠道的审批消息以带口令说明的纯文本呈现。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-020
  - docs/WorkFleet-V0.0.4/00_governance/glossary.md（审批、暂存）
- 契约：
  - `packages/contracts/commands/im-commands.json`（`Y{n} / N{n}`，permission `approval.decide_low`）
  - `packages/contracts/schemas/entities/approval.schema.json`（shortCode 1–99、risk、options[kind allow_once|allow_always|reject|custom]、expiresAt、decidedBy 可为 recipientId）、`protocol/frames/approval.decision.schema.json`
  - `packages/contracts/identity/permissions.json`（`approval.decide_high` 与设备所有者 extraRule）
  - `packages/contracts/adapters/channel-capabilities.schema.json`（`buttons=false` 时走文本渲染）；`errors/error-codes.json`：`APPROVAL_EXPIRED`、`APPROVAL_ALREADY_DECIDED`、`FORBIDDEN`
  - 表：`approvals`（`ux_approvals_code(tenant_id, short_code) WHERE status='pending'`）
- 前置任务：TASK-028、TASK-044
- 前置状态：TASK-028（`approvals.decide()`、`findPendingByShortCode()`）与 TASK-044（IM 入站指令执行、`linkedPrincipal`）已合并；TASK-045 的 `registerBlockRenderer` 可用

## 4. 输出
- `apps/relay/src/modules/commands/application/approval-codes/{handler.ts,index.ts}`：注册 `Y{n}/N{n}` 执行器（经 TASK-024 注册表）
- `apps/relay/src/modules/approvals/application/text-codes/{render.ts,index.ts}`：向 delivery 注册 `approval` 块的无按钮文本渲染器
- 测试：`apps/relay/tests/unit/modules/commands/approval-codes/**`、`apps/relay/tests/unit/modules/approvals/text-codes/**`

## 5. Execution Steps
1. [ ] 执行器：解析 n（1–99，大小写不敏感，全角 `Ｙ３` 归一化）；`findPendingByShortCode(tenantId, n)` 不存在→回“没有编号为 n 的待审批”。
2. [ ] 选项映射：Y → 优先 `allow_once`，无则 `allow_always`，再无则第一个非 reject 选项；N → `kind=reject` 选项；以 `recipients.linkedPrincipal` 为决策人调用 `approvals.decide()`（decidedBy 记 recipientId）。
3. [ ] 错误回发：`APPROVAL_EXPIRED`→“#n 已过期（已自动拒绝）”；`APPROVAL_ALREADY_DECIDED`→“#n 已由他人处理：<结果>”；`FORBIDDEN`（高风险且非管理员/设备所有者）→“#n 为高风险操作，需管理员或设备所有者审批”。
4. [ ] 文本渲染器：`【审批 #n｜风险：高】<summary>\n回复 Yn 批准，Nn 拒绝（HH:mm 前有效）`（i18n；时间按接收人 quietHours.tz，缺省 Asia/Shanghai），在 `buttons=false` 渠道使用。
5. [ ] 测试：Y/N 各自选对 optionId；全角与小写；不存在/过期/已决/高风险无权四种回复；文本渲染包含 shortCode 与口令说明。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：单测：`Y3` 对含 allow_once/allow_always/reject 的审批选择 allow_once；`n3` 选择 reject；`Ｙ３` 与 `y3` 等价。
- [ ] AC-2：pending 审批不存在/已过期/已决定 → 回发对应提示，且 `approval.decision` 帧不重复发送。
- [ ] AC-3：高风险审批由非设备所有者 operator 回复 `Y1` → 收到需权限提示，审批仍为 pending。
- [ ] AC-4：对 `buttons=false` 的渠道，审批消息渲染为包含 `#n`、`Yn`、`Nn` 的纯文本；`buttons=true` 渠道不使用该渲染器。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/relay test tests/unit/modules/commands/approval-codes tests/unit/modules/approvals/text-codes
pnpm -F @workfleet/relay typecheck
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-047/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/relay/src/modules/approvals/application/text-codes/**`
- `apps/relay/src/modules/commands/application/approval-codes/**`
- 明确写出的测试目录（本模块专属；allowedPaths 未含测试路径，按任务指令 §3 在此显式声明，执行前须经主 Agent 确认）：
  - `apps/relay/tests/unit/modules/commands/approval-codes/**`
  - `apps/relay/tests/unit/modules/approvals/text-codes/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-047/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-047/` 除外）
- `apps/relay/src/modules/commands/**` 中除 `application/approval-codes/**` 外的路径（TASK-024）
- `apps/relay/src/modules/approvals/**` 中除 `application/text-codes/**` 外的路径（TASK-028）
- `apps/relay/src/modules/{delivery,routing,recipients}/**`

## 11. 依赖与阻塞
- Depends on：TASK-028, TASK-044
- Blocks：TASK-048
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - TASK-028 未公开 `findPendingByShortCode`/`decide`，或 TASK-045 未提供 `registerBlockRenderer` → blocked 提单对应任务
  - 模块注册：本卡两个子目录不含模块根 `index.ts`，需由 commands/approvals 模块的 `register()` 加载子目录 → 若 TASK-024/028 未提供子目录自动加载约定则 blocked
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：指令执行器 + 文本模板，规则由契约与 TASK-028 给定，sonnect 足够。

## 13. 升级条件
- Y/N 选项映射在真实智能体 options（如自定义 custom 选项）下产生歧义需定义新规则 → 升 opus
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
小　是否小于 2 小时：否

## 15. 风险与假设
- 假设：Y→allow_once 优先、N→reject 的映射为本卡假设（契约只写“批准/拒绝”）。
- 假设（NON_BLOCKING，U-02）：微信审批提示也计入主动额度，审批消息优先级应为 p1 以上（由 TASK-045 处理排序）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-047/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
