# TASK-105：S5 E2E：通知/团队/屏障（FakeChannel 飞书方言）

```yaml
id: TASK-105
slice: S5
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-QA
tier: sonnect
size: 中
title: "S5 E2E：通知/团队/屏障（FakeChannel 飞书方言）"
dependsOn: ["008", "101", "103", "104"]
blocks: ["210"]
reqs: "REQ-F-010/016/021"
allowedPaths: ["tests/e2e/s5/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S5（可演示：场景 2——三个来源汇总后分别发给老板与数据部；通知模式两人回话分会话）
- 来源需求：REQ-F-010/016/021
- 来源方案：ADR-011（E2E 仅 ubuntu）；DEC-029；slices.md S5 演示脚本（场景 2）

## 2. 目标
用真中转 + 真节点 + FakeAgent + FakeChannel（飞书方言）自动化验证 S5：通知模式两人回话分会话、团队模式入站只到一个目标、三来源屏障收齐/超时各只发一条汇总。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/04_planning/slices.md`（S5 行）
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-010/016/021`
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §3 端口段（5110–5119 E2E 中转实例）
- 契约：
  - `packages/contracts/api/relay.openapi.json`：routes、routes/dry-run、barriers、conversations/messages 端点
  - `packages/contracts/protocol/frames/agent.output|barrier.submit`
  - `packages/contracts/adapters/channel-kinds.v1.json`：feishu 能力（FakeChannel 方言按此声明）
  - `packages/contracts/errors/error-codes.json`：ROUTE_INVALID
  - `packages/contracts/ux/ux-states.json`：route_editor_dry_run、route_list
- 前置任务：TASK-101, TASK-103, TASK-104
- 前置状态：TASK-101/103/104 已合并；TASK-008 FakeChannel 支持飞书方言（卡片、按钮回调、消息编辑）

## 4. 输出
- `tests/e2e/s5/`：notification.spec.ts、team.spec.ts、barrier.spec.ts、fixtures（种子数据：3 个 FakeAgent、老板与数据部两个接收人）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-105/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 搭建夹具：5112 起中转，节点挂 3 个 FakeAgent（a1/a2/a3），FakeChannel 以 feishu 方言注册 2 个接收人（老板、数据部）。
2. [ ] 通知模式用例：a1 → {老板, 数据部} 绑定；a1 输出一条，两个接收人各收 1 条；二人分别回话，断言产生两个不同会话且 a1 分别收到。
3. [ ] 团队模式用例：{a1,a2} ↔ {老板, 数据部}；随机发送 50 条入站（含 @别名、引用回复、无指向），断言每条只到 1 个智能体；dry-run 结果与实际一致。
4. [ ] 屏障收齐用例：开 3 来源屏障，a1/a2/a3 提交，断言两接收人各只收到 1 条汇总。
5. [ ] 屏障超时用例：timeoutSec=10，仅 a1/a2 提交，断言汇总标注缺失 a3，且只发 1 条。
6. [ ] Playwright 驱动控制台：创建 team 绑定、配置屏障并在列表看到 complete/timed_out 状态（data-ux-state 断言）。
7. [ ] ubuntu 连续跑 3 次无抖动，日志与截图写入证据。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 通知模式两接收人回话 → 2 个独立 conversationId
- [ ] 团队模式 50 条入站，每条目标数 = 1
- [ ] 屏障收齐与超时两个用例，各接收人汇总消息计数均为 1；超时汇总包含缺失来源 a3
- [ ] Playwright 用例通过，截图存证
- [ ] 越界检查只输出 SCOPE OK

## 7. 验证命令
```bash
pnpm exec playwright test tests/e2e/s5 --reporter=list
for i in 1 2 3; do pnpm exec playwright test tests/e2e/s5 || exit 1; done
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(tests/e2e/s5/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-105/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-105/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `tests/e2e/s5/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-105/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/**
- packages/testkit/**（FakeChannel 方言缺失只提需求）
- tests/e2e/ 下其他切片目录

## 11. 依赖与阻塞
- Depends on：TASK-008, TASK-101, TASK-103, TASK-104
- Blocks：TASK-210
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - FakeChannel 无飞书方言（卡片/按钮回调/编辑），而 packages/testkit 不在本任务路径内 → blocked，向 Agent-QA testkit 维护任务提需求
  - 被测任务任一未通过自身验收

## 12. 建议执行档位
sonnect　理由：E2E 脚本编写，断言来自需求可验证陈述。

## 13. 升级条件
- E2E 暴露路由/屏障语义缺陷 → 升 opus 仲裁并回退被测任务
- 同一用例 2 次失败 → 熔断

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- 无 U-xx 直接关联。
- 老板/数据部字段差异（REQ-F-027）属 S7，本卡只断言条数与路由，不断言字段过滤。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - 规划：105 的依赖链中没有 TASK-008（FakeChannel），飞书方言由谁提供未分配

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-105/
- 验证者结论：
- 遗留问题 / 跟进项编号：
