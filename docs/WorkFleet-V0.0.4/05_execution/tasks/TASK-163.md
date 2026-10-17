# TASK-163：supervisor 把关分级（规则 + LLM，超限降级）与 supervisor 路由模式

```yaml
id: TASK-163
slice: S8
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Node
tier: opus
size: 大
title: "supervisor 把关分级（规则 + LLM，超限降级）与 supervisor 路由模式"
dependsOn: ["162"]
blocks: ["164"]
reqs: "REQ-F-022"
allowedPaths: ["apps/node/src/modules/supervisor/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S8
- 来源需求：REQ-F-022
- 来源方案：DEC-018（总控把关不可关）；DEC-043（超限降级为规则把关并通知）；ADR-013（规则把关兜底）；architecture §6.2

## 2. 目标
在节点实现总控把关：对受总控管理的每条智能体输出给出 reply/merge/escalate/drop 之一并记录理由（LLM 分级 + 规则兜底），超出费用上限时自动降级为纯规则把关并通知用户；把关不可关闭；全部行为在 CI 中以 FakeAgent + ReplayProvider 自动验证。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-022、REQ-NF-010）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.2、§6.2
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-013-总控的模型调用.md
  - docs/WorkFleet-V0.0.4/00_governance/glossary.md（把关分级 verdict）
  - docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md（DEC-018、DEC-043、DEC-044）
- 契约：
  - packages/contracts/protocol/frames/agent.output.schema.json（`supervisorVerdict` reply/merge/escalate/drop；`kind` final/status/error/digest）
  - packages/contracts/schemas/entities/approval.schema.json（`kind=supervisor_escalation`）；schemas/entities/route.schema.json（mode `supervisor`）；schemas/entities/agent.schema.json（kind `supervisor`）
  - packages/contracts/api/node-local.openapi.json：`GET/PUT /local/v1/supervisor`（modelProfileId、rules、systemPrompt；返回降级状态）
  - packages/contracts/events/domain-events.json：`supervisor.verdict`（幂等键 messageId）、`budget.exceeded`
  - packages/contracts/errors/error-codes.json：`BUDGET_EXCEEDED`（ui：总控横幅“已降级为规则把关”）、`MODEL_PROVIDER_ERROR`
  - database/migrations/node/0001_init.sql：`supervisor_settings`（rules、degraded_since）、`supervisor_verdicts`（verdict CHECK、reason、by_rules）
- 前置任务：TASK-162
- 前置状态：TASK-162 已合并（ModelProvider + ReplayProvider 可用）；TASK-161 的 checkBudget/recordUsage 可用；packages/testkit FakeAgent 可用。

## 4. 输出
- apps/node/src/modules/supervisor/domain/（Verdict 值对象、规则引擎、降级状态机）
- apps/node/src/modules/supervisor/application/grading/（`grade(output) → {verdict, reason, byRules}`；输出拦截与按 verdict 处置）
- apps/node/src/modules/supervisor/application/settings/、infrastructure/、interfaces/（`/local/v1/supervisor`）、index.ts
- apps/node/src/modules/supervisor/**/__tests__/ 与 `__fixtures__/model-replay/grading/*.jsonl`
- （application/chat、dispatch、import 留给 TASK-164/182）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-163/`（见 §8）

## 5. Execution Steps
1. [ ] 定义受管范围：哪些智能体输出必须经总控。契约中节点无从得知中转侧 route.mode，默认读取智能体 `config.supervised=true` 或 `kind` 关联的设置（推断），在 EVD 写明并报契约缺口。
2. [ ] 定义内部规则 schema（契约中 `rules` 为无类型数组）：`{when:{kind?, priority?, textMatches?, agentAlias?}, verdict, reason}`；内置不可删除的兜底规则：`kind=error`→escalate；`kind=status` 进度类→merge；空文本/重复→drop；其余 final→reply。
3. [ ] 实现 `grade()`：checkBudget 未超限且已配置 modelProfile → 调 LLM（系统提示 + 输出摘要，要求 JSON `{verdict, reason}`），JSON 非法/超时/提供方错误 → 回落规则（by_rules=1）；超限 → 直接规则。
4. [ ] 实现处置：reply→回发起人（agent.output 设 `supervisorVerdict=reply`）；merge→并入摘要缓冲，定时以 `kind=digest` 发出；escalate→生成 `approval(kind=supervisor_escalation)` 上报；drop→不外发。四种都写 `supervisor_verdicts` 并发 `supervisor.verdict`（按 messageId 幂等）。
5. [ ] 实现降级：收到 `budget.exceeded` 且 `onExceed=degrade_to_rules` → 置 `degraded_since`，发一条 p1 通知（“已降级为规则把关”）；`onExceed=pause` → 停止调用模型且所有输出按 escalate 处理（保守默认，推断，待裁决）；跨期后自动恢复并通知。
6. [ ] 实现“不可关闭”：设置中不存在开关；PUT 带未知字段（如 `enabled:false`）→ `VALIDATION_FAILED`；代码路径中受管输出不存在绕过 `grade()` 的分支（用单测 + 覆盖率证明）。
7. [ ] 录制回放夹具：为 reply/merge/escalate/drop 各录 ≥1 条 LLM 响应，外加“非法 JSON”“提供方 500”两条；CI 中模型调用一律走 TASK-162 提供的 `ReplayProvider`（录制回放，读取本模块 `__fixtures__/model-replay/*.jsonl`），智能体一律用 packages/testkit 的 FakeAgent；任何测试不得访问外网（CI 断网也必须通过）；测试 setup 在 `WF_NET_DISABLED=1` 时拦截 fetch/net 外呼并令测试失败。
8. [ ] 写测试并运行验证命令，存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 四分级用例（CI，FakeAgent + ReplayProvider）：LLM 路径下 reply/merge/escalate/drop 各 ≥1 例按期望处置，且 `supervisor_verdicts` 各有一行含非空 reason。
- [ ] 规则兜底用例：LLM 返回非法 JSON 与提供方 500 时 verdict 来自规则（`by_rules=1`），输出未丢失。
- [ ] 超限降级用例：把 dailyMicros 设为极小值，第 N+1 条输出前触发 `budget.exceeded`，之后全部 `by_rules=1`、`degraded_since` 非空、发出 1 条降级通知；GET /local/v1/supervisor 返回降级状态。
- [ ] 不可关闭用例：PUT `{enabled:false}` → 400 `VALIDATION_FAILED`；100 条受管输出 100% 产生 verdict 记录（无遗漏）。
- [ ] 同一 messageId 重复到达只产生 1 条 verdict（幂等）。
- [ ] 测试在断网环境通过（CI job 设置无网络或 fetch 拦截断言 0 外呼）。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-163/
WF_NET_DISABLED=1 pnpm --filter ./apps/node exec vitest run src/modules/supervisor --exclude 'src/modules/supervisor/application/{chat,dispatch,import}/**' --coverage --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-163/vitest.txt
pnpm --filter ./apps/node exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-163/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-163/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-163/
- `vitest.txt`（含 grading 覆盖率）、`tsc.txt`、`guard.txt`
- `verdict-cases.md`（每个用例的输入摘要、期望/实际 verdict、by_rules）
- `scope-and-rules.md`（受管范围判定、内部规则 schema、pause 语义的推断与待裁决项）

## 9. 允许修改
- `apps/node/src/modules/supervisor/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-163/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-163/` 除外，见 ownership-matrix §4）
- apps/node/src/modules/models/**（只用其公开 API）
- apps/node/src/modules/agents/**、sessions/**
- apps/relay/**（中转不得运行模型，REQ-C-006）

## 11. 依赖与阻塞
- Depends on：TASK-162
- Blocks：TASK-164
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 节点无法得知哪些输出属于 supervisor 模式绑定（agent.output/agent.prompt/agents.sync 均无 route.mode 信息）：若主 Agent 不接受 `config.supervised` 推断方案 → blocked，需契约变更（ADR + 券）。
  - `onExceed=pause` 与 DEC-018“不可关”的关系未裁定：本卡按“停模型 + 全部上报”实现；若用户裁定不同语义 → 停在该分支。
  - agents 模块未提供输出拦截点（输出在送 relay-link 前经过 supervisor）→ blocked，报跨模块接线。

## 12. 建议执行档位
opus　理由：需求级不可关闭约束 + 降级状态机 + LLM 输出解析的安全兜底，错误代价高（DEC-018）。

## 13. 升级条件
- 需要让把关可关闭、或改变 verdict 枚举 → fable（推翻需求/契约）。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
大　是否小于 2 小时：否　规则引擎、LLM 分级、降级、四类处置与夹具，约 2 天。

## 15. 风险与假设
- 假设：受管范围由智能体配置标记（推断）。
- 假设：merge 摘要按 10 分钟窗口或 20 条触发（推断，可配）。
- 风险：LLM 被智能体输出中的注入内容诱导给出 drop → 规则层对 `kind=error` 与审批类输出强制 escalate，LLM 不能覆盖。
- 风险：digest 发出频率与微信额度冲突 → 交由 delivery 合并（DEC-017）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-163/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-163.md`）
