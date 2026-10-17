# TASK-029：Web 审批卡与收件箱

```yaml
id: TASK-029
slice: S1
status: todo
owner: Agent-App
tier: sonnect
size: 小
title: "Web 审批卡与收件箱"
dependsOn: ["027", "028"]
blocks: ["030"]
reqs: "REQ-F-020"
allowedPaths: ["apps/web/src/features/approvals/**", "apps/web/src/pages/approvals/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-029/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S1
- 来源需求：REQ-F-020（tasks.v1.json 原值 `REQ-F-020`）
- 来源方案：REQ-F-020（Web 以按钮审批）、ux-states.json `approval_inbox`、error-codes.json（APPROVAL_EXPIRED 卡片置灰、APPROVAL_ALREADY_DECIDED 显示结果）

## 2. 目标
Web 在聊天流内把 `approval` IR 块渲染为可操作的审批卡，并提供审批收件箱页；高风险审批仅对有权限者可点，过期/已决状态按错误码规范呈现。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-020
  - docs/项目完整目录结构.txt §10.2
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/approvals`、`POST /api/v1/approvals/{approvalId}/decide`（`{optionId}`；`APPROVAL_EXPIRED`、`APPROVAL_ALREADY_DECIDED`、`FORBIDDEN`）、`GET /api/v1/stream`（审批状态更新）
  - `packages/contracts/schemas/entities/approval.schema.json`（shortCode、summary、risk、options[label,kind]、status、expiresAt）、`message-body.schema.json`（`{type:'approval', approvalId}` 块）
  - `packages/contracts/ux/ux-states.json` screen `approval_inbox`；`errors/error-codes.json` `ui` 列
  - `packages/contracts/identity/permissions.json`（`approval.decide_low`/`approval.decide_high`；设备所有者 extraRule 由服务端判定）
- 前置任务：TASK-027、TASK-028
- 前置状态：TASK-027（Web 智能体/指令/历史）与 TASK-028（审批 API）已合并；TASK-012 提供 `registerBlockRenderer`

## 4. 输出
- `apps/web/src/features/approvals/{components/ApprovalCard.tsx,components/ApprovalInbox.tsx,hooks,api,index.ts}`：在 `index.ts` 中调用 chat 的 `registerBlockRenderer('approval', ApprovalCard)`
- `apps/web/src/pages/approvals/{routes.tsx,ApprovalInboxPage.tsx}`（路由 `/approvals`，导航角标显示 pending 数）
- 同目录测试 `*.test.tsx`

## 5. Execution Steps
1. [ ] `api`：列表、决策（Idempotency-Key 防双击重复提交）；stream 中审批状态变化时刷新对应卡片。
2. [ ] `ApprovalCard`：显示 `#shortCode`、summary、风险徽标、倒计时（expiresAt）、选项按钮（label）；risk=high 且 `/me.permissions` 无 `approval.decide_high` 时按钮可点但提示“需管理员或设备所有者”（服务端最终判定）。
3. [ ] 错误处理：`APPROVAL_EXPIRED`→卡片置灰“已过期”；`APPROVAL_ALREADY_DECIDED`→刷新并显示最终结果；`FORBIDDEN`→Toast 说明所需角色。
4. [ ] 收件箱页：pending/全部切换，`approval_inbox` 6 态与 `data-ux-state`。
5. [ ] 测试：点击批准调用 decide 并显示结果；过期置灰；已决显示结果；高风险无权限提示；收件箱 6 态。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`pnpm -F @workfleet/web test src/features/approvals` 全绿。
- [ ] AC-2：聊天流中的 `approval` 块渲染为 `ApprovalCard`（经 registerBlockRenderer），点击选项发出 `POST /approvals/{id}/decide` 且带 Idempotency-Key；双击只发一次。
- [ ] AC-3：服务端返回 409 `APPROVAL_EXPIRED` → 卡片置灰并显示“已过期”；409 `APPROVAL_ALREADY_DECIDED` → 显示最终结果。
- [ ] AC-4：`approval_inbox` 6 态均有测试并断言 `data-ux-state`。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/web test src/features/approvals
pnpm -F @workfleet/web typecheck && pnpm -F @workfleet/web build
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-029/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/web/src/features/approvals/**`
- `apps/web/src/pages/approvals/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-029/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-029/` 除外）
- `apps/web/src/features/chat/**`（TASK-012/027；仅通过其 index 的扩展点注册）
- `apps/web/src/{app,components,data-access,lib,styles,i18n}/**`（TASK-009）
- `apps/relay/**`、`apps/node/**`

## 11. 依赖与阻塞
- Depends on：TASK-027, TASK-028
- Blocks：TASK-030
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - TASK-012 未导出 `registerBlockRenderer` → blocked 提单 TASK-012
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：单一功能域 UI，规则已由契约给定，sonnect 足够。

## 13. 升级条件
- 审批交互在 TASK-030 E2E 中连续 2 次失败且非服务端原因 → 升 opus 复核
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
小　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-07）：移动端推送提醒审批在 TASK-203/204，本卡只做页面内。
- 本卡不涉及 U-02…U-06、U-08。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-029/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
