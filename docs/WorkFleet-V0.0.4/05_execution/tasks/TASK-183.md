# TASK-183：Web：会议回放与任务看板

```yaml
id: TASK-183
slice: S9
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-App
tier: sonnect
size: 中
title: "Web：会议回放与任务看板"
dependsOn: ["165", "181"]
blocks: ["184"]
reqs: "REQ-F-024/025"
allowedPaths: ["apps/web/src/features/meetings/**", "apps/web/src/features/tasks/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S9
- 来源需求：REQ-F-024 / REQ-F-025
- 来源方案：ADR-008；REQ-F-024（会议四类事件可回放）；REQ-F-025（任务看板）

## 2. 目标
在 Web 提供会议回放（按轮次时间线展示发言、纪要、决策）与总控任务看板（按状态分列、显示依赖与分派对象），实现统一的 6 种 UX 状态。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-008-前端.md
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-024/025）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §7（会议全量只在节点）
- 契约：
  - packages/contracts/schemas/entities/meeting.schema.json；node 迁移 `meeting_events.kind` 枚举（round_opened/speech/minutes/decision/round_closed）
  - packages/contracts/ux/ux-states.json（6 态规范；**无 meeting/task 看板 screen**）
  - **缺失**：node-local.openapi.json 与 relay.openapi.json 在已扫描范围内均无会议列表/回放、总控任务列表端点（见阻塞条件）
  - database/migrations/node/0001_init.sql：`meetings`、`meeting_events`、`supervisor_tasks`（字段作为视图模型参考）
- 前置任务：TASK-165, TASK-181
- 前置状态：TASK-165、TASK-181 已合并；契约补充会议/任务读取端点（若未补，按阻塞条件处理）。

## 4. 输出
- apps/web/src/features/meetings/（会议列表、回放时间线组件、事件卡片、纪要四段渲染、决策与生成任务链接）
- apps/web/src/features/tasks/（看板：pending/dispatched/running/done/failed/unassigned 列，依赖连线或标注，分派对象）
- 两目录内 data-access 端口（接口 + MSW 夹具实现）与 `__tests__/*.test.tsx`
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-183/`（见 §8）

## 5. Execution Steps
1. [ ] 先核对契约：若会议/任务读取端点仍缺失，按阻塞条件标 blocked 并只完成第 2–5 步中“对端口编程”的部分。
2. [ ] 定义 data-access 端口 `MeetingsPort`（list、getReplay）与 `TasksPort`（list），类型由 node 迁移字段与 meeting.schema.json 推导；提供 MSW 夹具（来自 TASK-181 的 `replay-sample.json`）。
3. [ ] 会议回放：按轮次分组的时间线，speech 显示参与者别名，round_closed 标注缺席者，minutes 按四段渲染，decision 链接到生成的任务。
4. [ ] 任务看板：按 state 分列，卡片显示 title、来源（meeting/import/chat）、分派智能体、依赖未满足提示；unassigned 列显示“需要映射 owner”。
5. [ ] 两个视图实现 empty/loading/error/no_permission/success/offline 并加 `data-ux-state`。
6. [ ] 写组件测试并运行验证命令，存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 用 TASK-181 回放样例渲染，四类事件（轮次、发言、纪要、决策）全部可见且顺序与 `(round, id)` 一致（组件测试）。
- [ ] 看板按 state 分列并正确显示依赖未满足与 unassigned（组件测试）。
- [ ] 两个视图 × 6 态可用 `data-ux-state` 断言。
- [ ] `pnpm --filter ./apps/web build` 成功；`make guard` 通过。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-183/
pnpm --filter ./apps/web exec vitest run src/features/meetings src/features/tasks --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-183/vitest.txt
pnpm --filter ./apps/web build | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-183/build.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-183/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-183/
- `vitest.txt`、`build.txt`、`guard.txt`
- `screenshots/`（回放、看板）
- `contract-gap.md`（缺失端点说明）

## 9. 允许修改
- `apps/web/src/features/meetings/**`
- `apps/web/src/features/tasks/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-183/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-183/` 除外，见 ownership-matrix §4）
- apps/web/src/pages/**、app/**、targets/node/**（页面挂载不在本卡路径）

## 11. 依赖与阻塞
- Depends on：TASK-165, TASK-181
- Blocks：TASK-184
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - **契约缺失**：无会议/总控任务读取 API。会议全量只在节点（architecture §7），因此应是 node-local 端点（且挂在本机控制台）；本卡允许路径只有 features/，无法挂页面 → 端口与组件可先做，数据接线与页面挂载 blocked，需主 Agent 发起契约变更 + 页面挂载任务。
  - ux-states.json 无对应 screen：按通用 6 态实现，报缺陷。

## 12. 建议执行档位
sonnect　理由：展示型组件，数据结构由迁移与 181 样例确定。

## 13. 升级条件
- 无。契约缺失属规划缺陷，交主 Agent。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：会议与任务视图属于本机控制台（node 构建目标），中转控制台只看外发摘要（推断，architecture §7）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-183/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-183.md`）
