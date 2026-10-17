# TASK-030：S1 E2E：多轮、/clear、/history、审批、held

```yaml
id: TASK-030
slice: S1
status: todo
owner: Agent-QA
tier: sonnect
size: 中
title: "S1 E2E：多轮、/clear、/history、审批、held"
dependsOn: ["022", "023", "028", "029"]
blocks: []
reqs: "REQ-F-018/019/020"
allowedPaths: ["tests/e2e/s1/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-030/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S1
- 来源需求：REQ-F-018、REQ-F-019、REQ-F-020（tasks.v1.json 原值 `REQ-F-018/019/020`）
- 来源方案：slices.md S1 演示脚本（多轮对话、/clear、/history、审批一次文件写入）、REQ-F-018/019/020、REQ-NF-009（CI 用 FakeAgent）

## 2. 目标
Playwright 在真中转 + 真节点 + ACP Host（拉起 FakeAgent 回放夹具）下自动验证 S1：多轮对话、`/clear` 后 generation+1 且旧记录可查、`/history` 指令、审批批准与超时拒绝、审批期间 held 并按序放行。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/04_planning/slices.md S1
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-018、REQ-F-019、REQ-F-020
  - packages/testkit/fixtures/acp/README.md
- 契约：
  - `packages/contracts/commands/im-commands.json`（`/clear`、`/history`、`/status`）
  - `packages/contracts/api/relay.openapi.json`：`POST /api/v1/conversations/{conversationId}/messages`、`POST /api/v1/conversations/{conversationId}/clear`、`GET /api/v1/history/search`、`GET /api/v1/approvals`、`POST /api/v1/approvals/{approvalId}/decide`
  - `packages/contracts/protocol/frames/{agent.prompt,agent.output,agent.clear,approval.request,approval.decision,history.query,history.result}.schema.json`
  - `packages/contracts/ux/ux-states.json`（`chat`、`approval_inbox`、`conversation_history` 的 `data-ux-state`）；`errors/error-codes.json`（`APPROVAL_EXPIRED`）
- 前置任务：TASK-022、TASK-023、TASK-028、TASK-029
- 前置状态：TASK-022、TASK-023、TASK-028、TASK-029 已合并（间接含 021/024/025/026/027）；TASK-013 的 `tests/e2e/support/**` 与 `playwright.config.ts` 可复用（只读）

## 4. 输出
- `tests/e2e/s1/multi-turn.spec.ts`、`tests/e2e/s1/clear-and-history.spec.ts`、`tests/e2e/s1/approval.spec.ts`、`tests/e2e/s1/held.spec.ts`
- `tests/e2e/s1/fixtures/adapters.local.json`（把 `fake-acp` 适配器指向 `fake-acp-agent --fixture …`，经节点数据目录覆盖文件加载，见 TASK-022）
- `tests/e2e/s1/helpers.ts`（`workfleet-node agent add --alias fa1 --adapter fake-acp …` 登记智能体、缩短审批超时的环境变量）

## 5. Execution Steps
1. [ ] 准备：每个用例新账号 + 新节点数据目录；把 `fixtures/adapters.local.json` 拷入节点数据目录；`agent add` 登记 `fa1`（夹具 basic）与 `fp1`（夹具 permission）。
2. [ ] multi-turn：与 `fa1` 连续 3 轮，断言 3 条回复按序出现且节点只拉起 1 个子进程（`/local/v1/status` 或日志断言）。
3. [ ] clear-and-history：发 `/clear` → 会话 displayId 不变、generation 显示 2；历史页按 displayId 查询能看到第 1 代消息；发 `/history <displayId> 2` 得到 system 消息含 2 条。
4. [ ] approval：向 `fp1` 发消息触发权限请求 → 聊天出现审批卡 → 点“允许一次” → 智能体继续并给出最终回复；另一用例设置极短超时（如 5 s）不操作 → 卡片置灰“已过期”，智能体收到拒绝。
5. [ ] held：审批 pending 时再发 2 条消息 → 界面标“暂存”；批准后 2 条按序被处理（回复顺序与发送顺序一致）。
6. [ ] 连续运行 3 次确认稳定，保存报告与日志。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`pnpm e2e tests/e2e/s1` 在 ubuntu 通过，连续 3 次全部 PASS。
- [ ] AC-2：`/clear` 后 generation=2，历史页按 displayId 可查到 generation=1 的消息（REQ-F-019）。
- [ ] AC-3：审批卡批准后智能体完成 turn；超时用例卡片显示“已过期”且智能体收到拒绝（REQ-F-020）。
- [ ] AC-4：pending 期间发送的 2 条消息在批准后按发送顺序得到回复（held，REQ-F-020）。
- [ ] AC-5：`/history` 指令返回 system 消息，条数与参数 n 一致（REQ-F-018）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。 E2E：`pnpm e2e <目录>`。
```bash
pnpm exec playwright install --with-deps chromium
pnpm e2e tests/e2e/s1
for i in 1 2 3; do pnpm e2e tests/e2e/s1 || exit 1; done
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-030/
- `test-output.txt`：3 次运行输出
- `playwright-report/`
- `logs/`：中转与节点日志（失败时）
- `summary.md`

## 9. 允许修改
- `tests/e2e/s1/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-030/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-030/` 除外）
- `playwright.config.ts`、`tests/e2e/support/**`、`tests/e2e/s0/**`（TASK-013 所有，只读复用；需改则 blocked 提单）
- `tests/e2e/s2/**` 等其他切片目录
- `apps/**`、`packages/**`（发现缺陷只记录退回）

## 11. 依赖与阻塞
- Depends on：TASK-022, TASK-023, TASK-028, TASK-029
- Blocks：—
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - `playwright.config.ts` 未按切片目录配置 project，导致无法单跑 `tests/e2e/s1` → blocked 提单 TASK-013
  - 节点 CLI `agent add` 或本地适配器覆盖文件机制缺失（TASK-021/022）→ 无法登记 FakeAgent 智能体 → blocked
  - 审批超时不可配置（无法在 E2E 中缩短）→ 超时用例改为单测覆盖并在完成记录登记
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：E2E 编写属主力档，失败只记录不修产品代码，sonnect 足够。

## 13. 升级条件
- 同代码下 E2E 连续 2 次时过时不过（审批/held 时序竞态）→ 升 opus 做跨模块时序排查
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：真机 Claude Code 冒烟由 TASK-022 完成，本卡只用回放夹具（REQ-NF-009）。
- 风险：held 顺序依赖中转按 held_at 放行与节点每会话串行两处共同保证，偶发乱序需同时排查 TASK-028 与 TASK-021。
- 本卡不涉及 U-02…U-08。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-030/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
