# TASK-103：orchestration：汇总屏障（N 来源或超时、缺失标注）

```yaml
id: TASK-103
slice: S5
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Relay
tier: sonnect
size: 中
title: "orchestration：汇总屏障（N 来源或超时、缺失标注）"
dependsOn: ["102"]
blocks: ["104", "105"]
reqs: "REQ-F-021"
allowedPaths: ["apps/relay/src/modules/orchestration/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S5（可演示：场景 2——三个来源汇总后分别发给老板与数据部；通知模式两人回话分会话）
- 来源需求：REQ-F-021
- 来源方案：G1、DEC-053；architecture §4.1 orchestration（不得调用模型）、§6.3

## 2. 目标
中转 orchestration 模块实现汇总屏障：为团队/通知绑定开屏障，收齐 N 个期望来源或超时后只发出一条汇总消息，超时时在汇总中标注缺失来源；重启后未关闭的屏障继续计时。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §4.1 orchestration、§6.3（汇总任务经屏障收齐后发出）
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-021-汇总屏障.md`
  - `docs/WorkFleet-V0.0.4/00_governance/glossary.md`（汇总屏障 barrier）
- 契约：
  - `packages/contracts/schemas/entities/barrier.schema.json`（expectedSources minItems 2、received、timeoutSec 10–86400、status open/complete/timed_out/cancelled、openedAt/closedAt）
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/barriers`（route.read）、`POST /api/v1/barriers`（route.write；body routeId+expectedSources+timeoutSec）
  - `packages/contracts/protocol/frames/barrier.submit.schema.json`（node→relay：barrierId、agentId、messageId）；`agent.output`（kind=digest）
  - `packages/contracts/api/node-local.openapi.json`：`POST /hooks/{hookId}` body.barrierId（Webhook 来源提交）
  - `packages/contracts/events/domain-events.json`：barrier.closed（幂等键 barrierId）
  - `packages/contracts/errors/error-codes.json`：VALIDATION_FAILED、NOT_FOUND、FORBIDDEN、ROUTE_INVALID
  - `database/migrations/relay/0001_init.sql`：`barriers`（expected_sources JSON、summary_message_id）、`barrier_submissions`（PK barrier_id+agent_id，天然去重）、`messages`、`deliveries`
- 前置任务：TASK-102
- 前置状态：TASK-102 已合并（team/notification 绑定可用）；conversations.appendMessage 与 delivery.enqueue 公开 API 可用

## 4. 输出
- `apps/relay/src/modules/orchestration/domain/`：Barrier 状态机（open→complete|timed_out|cancelled）
- `apps/relay/src/modules/orchestration/application/`：openBarrier、submit、closeOnTimeout、recoverOnBoot、composeSummary
- `apps/relay/src/modules/orchestration/infrastructure/`：barriers/barrier_submissions 仓储、定时器
- `apps/relay/src/modules/orchestration/interfaces/`：`GET/POST /api/v1/barriers` 路由、barrier.submit 帧处理器（经 node-gateway 订阅）
- `apps/relay/src/modules/orchestration/index.ts`、`__tests__/`
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-103/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 实现 openBarrier：校验 route 存在且 mode ∈ {team, notification}（否则 ROUTE_INVALID），expectedSources ⊆ route.sources 且 ≥2，timeoutSec 在 10–86400。
2. [ ] 实现 submit：处理 barrier.submit 帧与 Webhook 带 barrierId 的提交；非期望来源或屏障已关闭 → 忽略并审计；重复提交依赖 PK 去重。
3. [ ] 收齐：received == expectedSources 时在单事务内置 complete、生成汇总、写 summary_message_id，发出 barrier.closed。
4. [ ] 超时：定时器到期置 timed_out，汇总中按 expectedSources 顺序列出已提交内容，并显式标注缺失来源（别名列表）。
5. [ ] 汇总只做确定性拼接（按来源顺序、来源标题 + 正文），不调用任何模型；通过 conversations.appendMessage 写一条 kind=digest 消息，再按绑定 targets 交给 delivery。
6. [ ] recoverOnBoot：启动时扫描 status=open 的屏障，已过期立即关闭，未过期重建定时器。
7. [ ] 确保“只发出一条”：以 barrierId 作为汇总消息幂等键，并发收齐与超时竞争时只有一个成功（乐观条件更新 status='open'）。
8. [ ] 写测试：全部提交、部分提交后超时、重复提交、竞争条件、重启恢复、非法 route 模式。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 3 个来源全部提交 → 恰好 1 条汇总消息、status=complete、barrier.closed 发出 1 次
- [ ] 2/3 提交后超时 → 1 条汇总且正文标注缺失来源别名、status=timed_out
- [ ] 收齐与超时并发 100 次竞争测试，汇总消息总数恒为 1
- [ ] 重启后未过期屏障继续计时并按时关闭（假时钟测试）
- [ ] `POST /barriers` 响应通过 barrier.schema.json 校验；对 management 绑定返回 ROUTE_INVALID
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过（orchestration 不依赖模型相关模块）

## 7. 验证命令
```bash
pnpm --filter @workfleet/relay exec vitest run src/modules/orchestration
pnpm --filter @workfleet/relay exec tsc --noEmit
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/relay/src/modules/orchestration/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-103/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-103/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `apps/relay/src/modules/orchestration/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-103/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/relay/src/modules/routing/**
- apps/relay/src/modules/node-gateway/**（只订阅其公开帧事件）
- apps/relay/src/modules/permissions-filter/**（老板/数据部字段差异属 TASK-142）

## 11. 依赖与阻塞
- Depends on：TASK-102
- Blocks：TASK-104, TASK-105
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - node-gateway 未提供按帧类型订阅 barrier.submit 的公开 API
  - Webhook 提交（body.barrierId）到达中转时缺少 agentId/messageId 映射规则
  - 需要取消屏障或查询单个屏障的端点（契约只有列表与创建）

## 12. 建议执行档位
sonnect　理由：状态机与定时逻辑，规则明确、可用假时钟完全测试。

## 13. 升级条件
- 汇总内容需要模型生成（总控）→ 不在本模块，升 opus 重新划分（architecture：orchestration 不得调用模型）
- 竞争条件测试 2 次失败 → 熔断并升 opus 评审

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- 无 U-xx 直接关联。
- 假设：汇总格式为确定性拼接；面向老板与数据部的字段差异由 TASK-142 在出站前处理（S7）。
- barriers 表无 tenant_id，多租户隔离依赖 route→tenant 关联查询。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - Agent-Contract：barrier.schema 无“缺失来源”与 summaryMessageId 字段（表有 summary_message_id），API 无单个查询/取消端点，`POST /barriers` 的 x-errors 为空
  - Agent-Data：barriers 表缺 tenant_id

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-103/
- 验证者结论：
- 遗留问题 / 跟进项编号：
