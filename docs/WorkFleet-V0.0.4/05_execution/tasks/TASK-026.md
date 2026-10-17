# TASK-026：agents-registry：agents.sync、智能体 CRUD 下发与别名唯一

```yaml
id: TASK-026
slice: S1
status: todo
owner: Agent-Relay
tier: sonnect
size: 中
title: "agents-registry：agents.sync、智能体 CRUD 下发与别名唯一"
dependsOn: ["006"]
blocks: ["027", "028"]
reqs: "REQ-F-007"
allowedPaths: ["apps/relay/src/modules/agents-registry/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-026/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S1
- 来源需求：REQ-F-007（tasks.v1.json 原值 `REQ-F-007`）
- 来源方案：architecture §4.1（agents-registry：智能体元数据由节点上报，`findAgentByAlias()`）、ADR-007、glossary（别名：组织内唯一短名）

## 2. 目标
中转维护智能体登记表：接收节点 `hello.agents`/`agents.sync` 全量上报并入库，提供智能体列表/修改/删除 API 与输入适配器表 API，别名在组织内唯一（冲突返回 `ALIAS_TAKEN`）。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.1
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-007-输入端.md
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-007、REQ-F-004（智能体必须归属一个项目）
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/agents`（agent.read；summary 称可按 projectId/deviceId 过滤但未声明参数）、`POST /api/v1/agents`（agent.write；`{deviceId,projectId,alias,adapterId,config}`；`ALIAS_TAKEN`、`DEVICE_OFFLINE`、`VALIDATION_FAILED`）、`PATCH /api/v1/agents/{agentId}`、`DELETE /api/v1/agents/{agentId}`、`GET /api/v1/adapters/input`（InputAdapterSpec[]）
  - `packages/contracts/protocol/frames/agents.sync.schema.json`（node→relay，agents: Agent[]）、`hello.schema.json`（agents）、`error.schema.json`（code `ALIAS_TAKEN`、refSeq）
  - `packages/contracts/schemas/entities/agent.schema.json`（alias `^[a-z][a-z0-9_-]{0,31}$`、kind acp|coze|webhook|supervisor、writeMode、status、experimental）、`adapters/input-adapters.v1.json`
  - 表：`agents`（`ux_agents_alias(tenant_id, alias) WHERE deleted_at IS NULL`、config、version）、`devices`、`projects`（默认项目）
- 前置任务：TASK-006
- 前置状态：TASK-006 已合并（`onNodeFrame`、设备→tenant 解析、hello 处理钩子）

## 4. 输出
- `apps/relay/src/modules/agents-registry/{domain,application,interfaces/http,interfaces/node,infrastructure}/**`、`index.ts`（公开 `findAgentByAlias(tenantId, alias)`、`getAgent()`、`listAgents()`）
- 测试：`apps/relay/tests/unit/modules/agents-registry/**`、`apps/relay/tests/integration/modules/agents-registry/**`

## 5. Execution Steps
1. [ ] 订阅 `agents.sync` 与 hello 中的 `agents`：以设备所属 tenant 覆盖帧内 tenantId（防伪造）；按 id upsert；该设备上本次未出现的智能体置 `status=unavailable`（不删除，保留会话引用）。
2. [ ] projectId 处理：帧内 projectId 不属于本组织或为占位 `prj_00000000000000000000000000`（TASK-021 的权宜值）→ 映射到该组织默认项目（TASK-005 创建），并在日志记录映射。
3. [ ] 别名唯一：upsert/PATCH 时若 `(tenant, alias)` 冲突→HTTP 409 `ALIAS_TAKEN`；来自节点的冲突→回 `error{code:'ALIAS_TAKEN', refSeq}` 帧并跳过该条。
4. [ ] HTTP：`GET /agents`（支持 `projectId`/`deviceId` 查询参数——契约未声明，按 summary 实现并登记）、`PATCH`（alias/projectId，乐观锁 version→`CONFLICT`）、`DELETE`（软删除）。
5. [ ] `POST /agents`：校验 body 与 adapterId 存在、alias 唯一、设备在线（离线→409 `DEVICE_OFFLINE`）；因契约无中转→节点登记帧，在线时也无法下发，故本卡**不实现下发、不落库**：校验通过后返回 500 `INTERNAL`，`details.reason=agent_provisioning_unavailable`（契约无合适错误码，已登记），并在完成记录登记为 blocked 子项（见阻塞条件）。
6. [ ] `GET /adapters/input`：返回契约内置表（节点探测结果无上报帧，暂不合并，已登记）。
7. [ ] 测试：sync upsert 与 unavailable 标记；跨组织伪造 tenantId 被覆盖；别名冲突 HTTP 409 与 error 帧；占位 projectId 映射默认项目；列表过滤。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：FakeRelay 对偶测试：节点发 `agents.sync{agents:[a1,a2]}` → `GET /api/v1/agents` 返回 2 条，tenantId 等于设备所属组织；再发只含 a1 的 sync → a2 `status=unavailable`。
- [ ] AC-2：`PATCH /api/v1/agents/{agentId}` 改为已占用的 alias → 409 `ALIAS_TAKEN`；节点上报冲突别名 → 收到 `error{code:"ALIAS_TAKEN"}` 帧。
- [ ] AC-3：projectId 为占位值的智能体入库后 `projectId` = 组织默认项目 id。
- [ ] AC-4：`GET /api/v1/adapters/input` 返回 15 项且每项通过 `input-adapter-spec.schema.json`。
- [ ] AC-5：viewer 调 `PATCH/DELETE /agents` → 403 `FORBIDDEN`；他组织 agentId → 404 `NOT_FOUND`。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/relay test tests/unit/modules/agents-registry tests/integration/modules/agents-registry
pnpm -F @workfleet/relay typecheck
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-026/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/relay/src/modules/agents-registry/**`
- 明确写出的测试目录（本模块专属；allowedPaths 未含测试路径，按任务指令 §3 在此显式声明，执行前须经主 Agent 确认）：
  - `apps/relay/tests/unit/modules/agents-registry/**`
  - `apps/relay/tests/integration/modules/agents-registry/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-026/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-026/` 除外）
- `apps/relay/src/modules/{devices,node-gateway,conversations,projects}/**`
- `apps/node/**`、`apps/web/**`

## 11. 依赖与阻塞
- Depends on：TASK-006
- Blocks：TASK-027, TASK-028
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 契约缺“中转→节点”智能体登记/更新/删除帧（envelope 的 type 枚举仅有 node→relay 的 `agents.sync`）→ “CRUD 下发”无法实现：本卡完成登记表、别名唯一与查询，`POST /api/v1/agents` 下发子项 blocked，需 Agent-Contract 新增帧（如 `agents.upsert`/`agents.remove`）+ ADR
  - `agent.schema.json` 无 `config` 字段，而 `POST /api/v1/agents` 请求含 `config`、表 `agents.config` 存在 → 节点无法经 `agents.sync` 回传 config；契约缺口已报告
  - `GET /api/v1/adapters/input` 要求合并节点探测结果但无上报帧 → 已报告
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：登记表与 CRUD 属常规实现，sonnect 足够；无法实现的下发部分已明确 blocked，不由执行者自行设计协议。

## 13. 升级条件
- 主 Agent 批准新增下发帧后，帧语义评审 → 升 opus（契约语义）
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：占位 projectId 映射默认项目为 S1 权宜方案（项目模块 TASK-061 在 S3）。
- 风险：节点全量 sync 与控制台修改并发时别名覆盖 → 以 version 乐观锁 + 节点为准的冲突策略，待评审。
- 本卡不涉及 U-02…U-08。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-026/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
