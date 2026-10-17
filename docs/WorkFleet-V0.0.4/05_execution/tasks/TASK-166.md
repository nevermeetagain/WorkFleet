# TASK-166：S8 E2E：把关四分级、超限降级、随时对话不打断

```yaml
id: TASK-166
slice: S8
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-QA
tier: sonnect
size: 中
title: "S8 E2E：把关四分级、超限降级、随时对话不打断"
dependsOn: ["164", "165"]
blocks: ["210"]
reqs: "REQ-F-022/023/026"
allowedPaths: ["tests/e2e/s8/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S8
- 来源需求：REQ-F-022 / REQ-F-023 / REQ-F-026
- 来源方案：slices.md S8 演示脚本：配模型与日上限；总控对每条输出分级；超限降级；/boss 对话不打断任务

## 2. 目标
用 Playwright 在“真中转 + 真节点 + FakeAgent + ReplayProvider”环境端到端验证 S8：把关四分级、超限降级、/boss 不打断任务，以及模型 Key 不出节点（中转库与日志 grep 不到）。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/04_planning/slices.md（S8 行）
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-022/023/026、REQ-NF-010）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §3（E2E 端口 5110–5119）
- 契约：
  - packages/contracts/ux/ux-states.json（`data-ux-state` 断言）；protocol/frames/agent.output.schema.json（supervisorVerdict）
  - packages/contracts/api/relay.openapi.json：`/api/v1/conversations/{id}/messages`、`/api/v1/approvals`、`/api/v1/stream`
  - packages/contracts/api/node-local.openapi.json：`/local/v1/model-profiles`、`/local/v1/usage`、`/local/v1/supervisor`
  - packages/contracts/errors/error-codes.json：`BUDGET_EXCEEDED`
- 前置任务：TASK-164, TASK-165
- 前置状态：TASK-164、TASK-165 已合并；TASK-013 的 Playwright 基座（起中转与节点、FakeAgent 注入）可复用；节点支持以环境变量启用 ReplayProvider（TASK-162）。

## 4. 输出
- tests/e2e/s8/supervisor-grading.spec.ts（四分级）
- tests/e2e/s8/budget-degrade.spec.ts（超限降级）
- tests/e2e/s8/boss-no-interrupt.spec.ts（随时对话不打断）
- tests/e2e/s8/key-isolation.spec.ts（Key 不出节点）
- tests/e2e/s8/fixtures/（FakeAgent 脚本、模型回放 JSONL）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-166/`（见 §8）

## 5. Execution Steps
1. [ ] 准备夹具：FakeAgent 脚本输出 4 类可被分级的样本（正常结论、进度、错误、空/重复）；ReplayProvider 回放对应 verdict；一段长任务脚本（20 条输出）。
2. [ ] supervisor-grading：在本机控制台配置模型与受管智能体 → Web 发任务 → 断言 reply 出现在会话、merge 以 digest 出现、escalate 出现在审批收件箱（kind supervisor_escalation）、drop 不外发但本机记录可见。
3. [ ] budget-degrade：设极小 dailyMicros → 触发超限 → 断言 Web/本机出现降级横幅（`BUDGET_EXCEEDED` 文案）、之后的 verdict 来自规则、收到 1 条降级通知。
4. [ ] boss-no-interrupt：长任务运行中通过 Web 发 3 条 `/boss` → 断言总控回复与长任务 20 条输出全部到达且顺序不变。
5. [ ] key-isolation：用固定测试 Key 创建配置并完成上述流程后，读取中转 SQLite 文件与日志文件 grep 测试 Key 0 命中。
6. [ ] 在 CI（ubuntu，断网的模型出口）运行，导出 HTML 报告与 trace 存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 四分级 E2E：reply/merge/escalate/drop 各 ≥1 例在 UI 上表现符合期望。
- [ ] 超限降级 E2E：横幅出现、后续分级 by_rules、通知 1 条。
- [ ] /boss 不打断 E2E：长任务输出 20/20 按序到达，/boss 3/3 有回复。
- [ ] Key 隔离：中转 relay.db 与日志中测试 Key 0 命中（REQ-F-026 原句）。
- [ ] 整套 E2E 连续运行 3 次全部通过（防偶发）。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-166/
pnpm exec playwright test tests/e2e/s8 --repeat-each=3 --reporter=list,html | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-166/playwright.txt
cp -r playwright-report docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-166/playwright-report
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-166/
- `playwright.txt`、`playwright-report/`（含 trace）
- `key-grep.txt`（grep 命令与 0 命中输出）

## 9. 允许修改
- `tests/e2e/s8/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-166/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-166/` 除外，见 ownership-matrix §4）
- apps/**、packages/testkit/**（缺能力时报主 Agent，不在本卡改实现）

## 11. 依赖与阻塞
- Depends on：TASK-164, TASK-165
- Blocks：TASK-210
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - E2E 中无法通过环境变量让节点使用 ReplayProvider（TASK-162/163 未提供注入点）→ blocked。
  - `/boss` 在中转侧未路由到总控（见 TASK-164 阻塞条件）→ blocked 并报缺陷。

## 12. 建议执行档位
sonnect　理由：E2E 脚本编写，判定标准已在本卡写死。

## 13. 升级条件
- E2E 暴露的问题需要跨模块仲裁（例如 merge 摘要触发时机与 delivery 合并冲突）→ opus。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：节点与中转在同一 CI 主机，时延不构成干扰。
- 风险：digest 定时窗口导致用例慢 → 用可配置短窗口（测试配置）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-166/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-166.md`）
