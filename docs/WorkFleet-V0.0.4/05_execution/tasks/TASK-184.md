# TASK-184：S9 E2E：会议与导入分派

```yaml
id: TASK-184
slice: S9
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-QA
tier: sonnect
size: 中
title: "S9 E2E：会议与导入分派"
dependsOn: ["181", "182", "183"]
blocks: ["210"]
reqs: "REQ-F-024/025"
allowedPaths: ["tests/e2e/s9/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S9
- 来源需求：REQ-F-024 / REQ-F-025
- 来源方案：slices.md S9 演示脚本：三个智能体开会出纪要与分派；导入任务卡目录直接分派

## 2. 目标
端到端验证 S9：3 个 FakeAgent 由总控组织会议、产出纪要与决策并分派任务；导入一个任务卡目录按依赖顺序分派；全部在 CI 中以真节点 + FakeAgent + ReplayProvider 自动运行。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/04_planning/slices.md（S9 行）
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-024/025）
  - docs/WorkFleet-V0.0.4/05_execution/task-template.md
- 契约：
  - packages/contracts/api/node-local.openapi.json：`POST /local/v1/supervisor/import-tasks`
  - packages/contracts/commands/im-commands.json：`/boss`（经总控发起会议）
  - packages/contracts/schemas/entities/meeting.schema.json；events/domain-events.json：`meeting.round_closed`
  - database/migrations/node/0001_init.sql：`meeting_events`、`supervisor_tasks`（断言读取）
- 前置任务：TASK-181, TASK-182, TASK-183
- 前置状态：TASK-181、TASK-182、TASK-183 已合并；TASK-166 的 E2E 基座（ReplayProvider 注入）可复用。

## 4. 输出
- tests/e2e/s9/meeting.spec.ts
- tests/e2e/s9/import-dispatch.spec.ts
- tests/e2e/s9/fixtures/（3 个 FakeAgent 会议脚本、模型回放 JSONL、任务卡目录：合法 4 卡含依赖、环 2 卡）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-184/`（见 §8）

## 5. Execution Steps
1. [ ] 准备夹具：FakeAgent a/b/c 的会议发言脚本（c 第 1 轮故意超时）；ReplayProvider 回放纪要/决策；任务卡目录（按 task-template 16 节格式）。
2. [ ] meeting.spec：经 Web `/boss` 发起“开会：主题 @a @b @c”→ 断言会议 2 轮完成、缺席标注、纪要四段、决策生成任务并被分派（FakeAgent 收到 prompt）；若 UI 可用（TASK-183 已挂载）则在回放页断言事件顺序，否则直接读 node.db 断言。
3. [ ] import-dispatch.spec：调用 import-tasks dryRun → 断言层级；正式导入 → 断言 4 卡按依赖顺序投递；环目录 → `VALIDATION_FAILED`。
4. [ ] 超时用例使用测试配置的短 roundTimeoutSec（30 s 为契约下限，必要时由节点测试时钟加速，推断）。
5. [ ] CI 运行 3 次，导出报告与 trace 存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 会议 E2E：2 轮、缺席 1 次、四类事件齐全、决策任务被分派。
- [ ] 导入 E2E：合法目录 4/4 按依赖顺序投递；环目录被拒且无写入。
- [ ] 两套用例在断网（模型出口）环境连续 3 次通过。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-184/
pnpm exec playwright test tests/e2e/s9 --repeat-each=3 --reporter=list,html | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-184/playwright.txt
cp -r playwright-report docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-184/playwright-report
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-184/
- `playwright.txt`、`playwright-report/`
- `meeting-replay.json`（E2E 中导出的事件序列）

## 9. 允许修改
- `tests/e2e/s9/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-184/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-184/` 除外，见 ownership-matrix §4）
- apps/**、packages/testkit/**

## 11. 依赖与阻塞
- Depends on：TASK-181, TASK-182, TASK-183
- Blocks：TASK-210
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 会议发起入口（/boss → 总控工具 → meetings）未接线（见 TASK-181 阻塞条件）→ blocked。
  - roundTimeoutSec 下限 30 s 使超时用例耗时过长且节点不支持测试时钟 → 报主 Agent 决定接受耗时或加时钟注入。

## 12. 建议执行档位
sonnect　理由：E2E 脚本编写，判定标准已在本卡写死。

## 13. 升级条件
- E2E 暴露会议状态机的竞态问题 → opus。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：E2E 中会议回放 UI 可能因契约缺失未挂载，退而读 node.db 断言（不影响 REQ-F-024 判定）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-184/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-184.md`）
