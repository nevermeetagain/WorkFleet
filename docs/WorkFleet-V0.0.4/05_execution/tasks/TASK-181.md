# TASK-181：meetings 引擎：轮次、发言、纪要、决策、全员或超时

```yaml
id: TASK-181
slice: S9
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Node
tier: opus
size: 大
title: "meetings 引擎：轮次、发言、纪要、决策、全员或超时"
dependsOn: ["164"]
blocks: ["183", "184"]
reqs: "REQ-F-024"
allowedPaths: ["apps/node/src/modules/meetings/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S9
- 来源需求：REQ-F-024
- 来源方案：DEC-019（会议结构化事件：会议/轮次/发言/纪要/决策；主持策略“全员提交或超时”；纪要四段式；纪要注入下一轮且按参与者定制）；DEC-043；architecture §6.2

## 2. 目标
在节点实现会议引擎：总控组织 ≥2 个智能体开会，按“全员提交或超时”推进轮次，产出发言、纪要、决策并可按事件顺序完整回放；决策可转为任务交给分派；超限时纪要降级为规则拼接、决策改为上报用户。全部在 CI 中以 FakeAgent + ReplayProvider 自动验证。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-024）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.2 meetings、§6.2
  - docs/WorkFleet-V0.0.4/00_governance/glossary.md（会议）
  - docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md（DEC-019、DEC-043）
- 契约：
  - packages/contracts/schemas/entities/meeting.schema.json（participants minItems 2、policy `all_or_timeout`、roundTimeoutSec 30–3600、maxRounds 1–10、status open/summarizing/decided/cancelled）
  - packages/contracts/events/domain-events.json：`meeting.round_closed`（幂等键 meetingId+round）
  - packages/contracts/schemas/entities/approval.schema.json（决策需用户确认时 `kind=major_decision` 或 `supervisor_escalation`）
  - packages/contracts/errors/error-codes.json：`AGENT_UNAVAILABLE`、`BUDGET_EXCEEDED`
  - database/migrations/node/0001_init.sql：`meetings`、`meeting_events`（kind round_opened/speech/minutes/decision/round_closed）、`supervisor_tasks`（source `meeting`）
- 前置任务：TASK-164
- 前置状态：TASK-164 已合并（总控会话、dispatch 用例、ReplayProvider 夹具机制）。

## 4. 输出
- apps/node/src/modules/meetings/domain/（Meeting 聚合、轮次状态机、主持策略 all_or_timeout）
- apps/node/src/modules/meetings/application/（startMeeting、onSpeech、closeRound、summarize、decide、replay）
- apps/node/src/modules/meetings/infrastructure/（meetings/meeting_events 仓储、计时器）
- apps/node/src/modules/meetings/index.ts（公开 `startMeeting`、`cancelMeeting`、`getReplay`）
- apps/node/src/modules/meetings/**/__tests__/ 与 `__fixtures__/model-replay/meetings/*.jsonl`
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-181/`（见 §8）

## 5. Execution Steps
1. [ ] 实现状态机：open →（每轮）round_opened → 收集 speech → 全员提交或 roundTimeoutSec 到期 → round_closed（发 `meeting.round_closed`）→ minutes → 下一轮或 summarizing → decision → decided；cancel 可在任意未决状态进入 cancelled。
2. [ ] 发言收集：为每位参与者开独立会议会话（与其执行会话隔离），投递本轮议题 + 上一轮纪要（按参与者定制：突出与其相关的待办，DEC-019）；超时未发言者记录为缺席事件内容。
3. [ ] 纪要：调用模型生成“四段式”纪要；DEC-019 的四段具体名称在 V0.0.3 引用的 BF `16 §10` 中，**本仓库已扫描范围内未找到其定义 → 证据不足**，默认采用“结论 / 分歧 / 待办 / 风险”（推断）并写入 EVD 待确认。
4. [ ] 决策：最后一轮后生成决策（选项 + 理由 + 任务清单）；任务经 TASK-164 的 dispatch 公开用例写入 `supervisor_tasks(source=meeting)`；高影响决策生成审批上报用户。
5. [ ] 降级：预算超限时纪要改为规则拼接（每人发言截断摘要），决策不自动做出而改为 escalate 给用户；记录 `by_rules` 标记于事件 content。
6. [ ] 回放：`getReplay(meetingId)` 按 (round, id) 返回全部事件，可重建完整会议；事件写入后不可修改。
7. [ ] 写测试：3 个 FakeAgent 开会，其中 1 个超时不发言、2 轮、ReplayProvider 回放纪要与决策；断言事件序列、缺席标注、任务生成；降级用例；参与者 <2 → VALIDATION_FAILED。
8. [ ] 运行验证命令并存证（`WF_NET_DISABLED=1` 下由测试 setup 拦截一切外呼）。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 3 智能体 × 2 轮用例：事件序列为 round_opened→speech×n→round_closed→minutes（每轮）→decision，`meeting_events` 可完整回放（CI，FakeAgent + ReplayProvider）。
- [ ] 超时用例：1 个参与者不发言时该轮在 roundTimeoutSec（测试用假时钟）后关闭并标注缺席，`meeting.round_closed` 只发 1 次。
- [ ] 决策生成的任务进入 `supervisor_tasks(source=meeting)` 并被分派（FakeAgent 收到 prompt）。
- [ ] 超限降级用例：纪要来自规则拼接、模型调用计数 0、决策以审批形式上报。
- [ ] 第二轮投递给每位参与者的上下文包含上一轮纪要且彼此不同（按参与者定制）。
- [ ] 测试断网通过；`make guard` 通过。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-181/
WF_NET_DISABLED=1 pnpm --filter ./apps/node exec vitest run src/modules/meetings --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-181/vitest.txt
pnpm --filter ./apps/node exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-181/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-181/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-181/
- `vitest.txt`、`tsc.txt`、`guard.txt`
- `replay-sample.json`（测试会议的完整事件回放）
- `minutes-format.md`（四段式取值与证据标签）

## 9. 允许修改
- `apps/node/src/modules/meetings/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-181/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-181/` 除外，见 ownership-matrix §4）
- apps/node/src/modules/supervisor/**（只调用其公开用例）
- apps/node/src/modules/agents/**、models/**

## 11. 依赖与阻塞
- Depends on：TASK-164
- Blocks：TASK-183, TASK-184
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 契约中没有发起/查询会议的接口（node-local.openapi.json 与 relay.openapi.json 已扫描范围内未找到 meetings 端点，也无会议相关帧）：本卡只提供进程内公开 API；用户如何发起会议需由 /boss 工具调用，而该工具注册在 TASK-164 目录 → 若 164 未提供工具注册表，标 blocked 报跨模块接线。
  - 参与者分布在不同设备上时节点无法驱动（会议仅限本节点智能体，推断）：若验收要求跨设备会议 → blocked，需协议扩展。

## 12. 建议执行档位
opus　理由：多智能体并发状态机 + 超时 + 降级 + 与分派的耦合，属本切片最高复杂度（关键路径节点）。

## 13. 升级条件
- 需要新增会议帧/端点 → fable 或 opus 契约审（改冻结契约）。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
大　是否小于 2 小时：否　状态机、计时器、纪要/决策、降级与回放，约 2 天。

## 15. 风险与假设
- 证据不足：纪要四段式的具体段名。
- 假设：会议仅限同一节点上的智能体（推断）。
- 风险：参与者长时间不响应时会议总时长 = maxRounds × roundTimeoutSec，最长 10 小时 → 允许用户取消。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-181/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-181.md`）
