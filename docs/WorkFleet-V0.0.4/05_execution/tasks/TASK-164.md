# TASK-164：总控随时对话（/boss）与任务分派

```yaml
id: TASK-164
slice: S8
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Node
tier: opus
size: 中
title: "总控随时对话（/boss）与任务分派"
dependsOn: ["163"]
blocks: ["166", "181", "182"]
reqs: "REQ-F-023"
allowedPaths: ["apps/node/src/modules/supervisor/application/chat/**", "apps/node/src/modules/supervisor/application/dispatch/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S8
- 来源需求：REQ-F-023
- 来源方案：DEC-043；REQ-F-023；architecture §6.2（随时对话走独立会话、不进入执行队列、不打断任务）；commands/im-commands.json `/boss`

## 2. 目标
用户可随时经 `/boss`（IM/Web）与总控对话：对话走独立会话、不暂停正在执行的任务、不丢消息；总控可把任务分派给 1..N 个智能体并跟踪状态；超限降级时仍可用确定性语法分派。全部在 CI 中以 FakeAgent + ReplayProvider 自动验证。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-023）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §6.2
  - docs/WorkFleet-V0.0.4/04_planning/cost-budget.md §3（S8 券制度：164 默认 sonnect 执行 + opus review）
  - docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md（DEC-043）
- 契约：
  - packages/contracts/commands/im-commands.json：`/boss <text>`（permission agent.prompt）
  - packages/contracts/protocol/frames/agent.prompt.schema.json、agent.output.schema.json、agent.status.schema.json（queueDepth）
  - packages/contracts/schemas/entities/agent.schema.json（kind `supervisor`）；schemas/common/ids.schema.json（`taskId`）
  - packages/contracts/errors/error-codes.json：`AGENT_UNAVAILABLE`、`AGENT_BUSY_WRITE_LEASE`、`BUDGET_EXCEEDED`
  - database/migrations/node/0001_init.sql：`supervisor_tasks`（source `chat`、assigned_agent_id、state、depends_on）、`sessions`、`prompt_queue`
- 前置任务：TASK-163
- 前置状态：TASK-163 已合并（grade、降级状态、ReplayProvider 夹具机制）。

## 4. 输出
- apps/node/src/modules/supervisor/application/chat/（总控会话：独立 conversation、上下文组装、工具 `dispatch_task`/`task_status`、降级时的确定性解析）
- apps/node/src/modules/supervisor/application/dispatch/（`dispatch(task, agentIds[])`：写 supervisor_tasks → 通过 agents 公开 API 投递 → 跟踪 state → 完成回报总控会话）
- 两目录内 `__tests__/` 与 `__fixtures__/model-replay/chat/*.jsonl`
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-164/`（见 §8）

## 5. Execution Steps
1. [ ] 实现总控会话：`/boss` 文本进入 supervisor 智能体自己的 conversation（与任何执行会话不同的 conversationId），由独立工作者处理，不入被分派智能体的 prompt_queue。
2. [ ] 上下文组装：最近 N 轮总控对话 + 当前 supervisor_tasks 状态摘要 + 智能体列表（别名/状态/queueDepth）；入站用户文本按不可信内容包裹。
3. [ ] 实现工具：`dispatch_task({title, spec, agentAliases[1..N], dependsOn?})`、`task_status({taskId?})`；LLM 工具调用经 ReplayProvider 回放。
4. [ ] 实现 dispatch：为每个目标智能体建一条 supervisor_tasks（source=chat），按依赖就绪后投递 prompt；目标不可用 → 状态 `failed` 并回报 `AGENT_UNAVAILABLE`；写租约冲突 → 回报 `AGENT_BUSY_WRITE_LEASE` 并保持 pending。
5. [ ] 降级（预算超限）：总控回复固定说明并接受确定性语法 `/boss @z1 @cc1 <任务>` 直接分派，不调用模型。
6. [ ] 写“不打断”测试：FakeAgent z1 执行一个脚本化长任务（持续输出 20 条 status/final），期间发 5 条 `/boss`；断言 z1 的 20 条输出全部按序到达、z1 未收到 cancel、总控 5 条全部有回复。
7. [ ] 写分派测试：一次分派给 3 个 FakeAgent，含 1 个依赖；断言顺序、状态流转与完成回报；降级下确定性语法分派成功。
8. [ ] CI 中模型调用一律走 TASK-162 提供的 `ReplayProvider`（录制回放，读取本模块 `__fixtures__/model-replay/*.jsonl`），智能体一律用 packages/testkit 的 FakeAgent；任何测试不得访问外网（CI 断网也必须通过）；测试 setup 在 `WF_NET_DISABLED=1` 时拦截 fetch/net 外呼并令测试失败。 运行验证命令并存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 不打断用例（CI）：长任务期间 5 条 `/boss` 均得到回复，执行中智能体 0 次 cancel、输出条数与顺序与无 /boss 基线一致（0 丢失）。
- [ ] 分派用例：1 次分派到 3 个智能体，supervisor_tasks 3 行状态正确流转至 done，依赖任务在前置完成后才投递。
- [ ] 超限降级用例：预算超限后 `/boss @a @b 任务` 不调用模型（ReplayProvider 调用计数 0）仍完成分派，自然语言请求得到“已降级”固定回复。
- [ ] 目标智能体不可用时返回 `AGENT_UNAVAILABLE` 并记录 failed，不影响其他目标。
- [ ] 测试断网通过；`make guard` 通过。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-164/
WF_NET_DISABLED=1 pnpm --filter ./apps/node exec vitest run src/modules/supervisor/application/chat src/modules/supervisor/application/dispatch --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-164/vitest.txt
pnpm --filter ./apps/node exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-164/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-164/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-164/
- `vitest.txt`、`tsc.txt`、`guard.txt`
- `no-interrupt-trace.md`（不打断用例的时间线：输出序号、/boss 时刻、回复时刻）
- `opus-review.md`（opus 档 review 结论，见 §12）

## 9. 允许修改
- `apps/node/src/modules/supervisor/application/chat/**`
- `apps/node/src/modules/supervisor/application/dispatch/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-164/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-164/` 除外，见 ownership-matrix §4）
- apps/node/src/modules/supervisor/ 下除 application/chat、application/dispatch 外文件（TASK-163/182）
- apps/node/src/modules/agents/**、sessions/**、meetings/**

## 11. 依赖与阻塞
- Depends on：TASK-163
- Blocks：TASK-166, TASK-181, TASK-182
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - agents 模块无“按 agentId 投递 prompt 并订阅其输出”的进程内公开 API → blocked，报跨模块接口。
  - 中转侧 `/boss` 指令如何映射到 supervisor 智能体（别名、所在设备=主设备）未在契约中定义：若 TASK-024 未实现该映射，E2E 层（TASK-166）会失败 → 报缺陷。

## 12. 建议执行档位
sonnect（执行）+ opus（review，占 S8 opus 券 1 张）　理由：复用 163 已定的模型/降级机制，主要是会话隔离与任务状态机的实现工作；风险点（不打断、不丢消息）由自动化用例锁定，再由 opus 复核。

**券制度说明**：yaml `tier` 按 tasks.v1.json 照写 `opus`。依据 `04_planning/cost-budget.md §3`，S8 有 161/163/164 三张 opus 执行卡 + 1 张切片前契约审 = 4 张，超出每切片 3 张上限；**默认执行方式改为 sonnect 执行 + opus review（占 1 券）**，用户批准超额后可恢复为 opus 执行。opus review 的结论写入 `EVD-164/opus-review.md`。

## 13. 升级条件
- opus review 判定会话隔离或分派状态机存在设计缺陷 → 改为 opus 执行（需用户批准超额券）。
- 需要中转侧配合（/boss 映射）改契约 → opus 契约审。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：总控智能体运行在主设备（REQ-F-005/devices `/primary` 注释“总控默认运行处”）。
- 风险：总控会话与长任务共用同一模型配置预算，/boss 频繁时更早触发降级。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-164/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-164.md`）
