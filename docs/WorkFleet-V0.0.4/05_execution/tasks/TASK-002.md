# TASK-002：契约包构建：JSON Schema→TS 类型生成、ajv 校验器导出、示例校验测试、生成物漂移检查

```yaml
id: TASK-002
slice: S0
status: todo
owner: Agent-Contract
tier: sonnect
size: 中
title: "契约包构建：JSON Schema→TS 类型生成、ajv 校验器导出、示例校验测试、生成物漂移检查"
dependsOn: ["001"]
blocks: ["004", "007", "008", "009", "014"]
reqs: "REQ-NF-009"
allowedPaths: ["packages/contracts/package.json", "packages/contracts/scripts/**", "packages/contracts/src/**", "packages/contracts/generated/**", "packages/contracts/test/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-002/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S0
- 来源需求：REQ-NF-009（tasks.v1.json 原值 `REQ-NF-009`）
- 来源方案：ADR-002（JSON Schema 2020-12 唯一源 + OpenAPI 3.1 编目；漂移检查 `pnpm contracts:gen && git diff --exit-code`）、ADR-012（ID/时间/金额格式）

## 2. 目标
让 `packages/contracts` 成为可被三端 import 的包：由全部 JSON Schema 生成 TS 类型与 ajv 校验器，`pnpm contracts:test` 验证 schema 合法、$ref 可解析、正反例符合预期、生成物无漂移。

## 3. 输入
- 文档：
  - packages/contracts/README.md
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-002-契约唯一源.md、ADR-012-全局命名与格式.md
  - docs/WorkFleet-V0.0.4/03_solution/contracts/README.md（需求→契约映射）
- 契约：
  - `packages/contracts/schemas/common/*.schema.json`（ids、timestamp、money、page、page-request、error）
  - `packages/contracts/schemas/entities/*.schema.json`（agent、approval、channel、conversation、delivery、device、message、message-body、recipient、route、user、tenant、membership、relay-link 等 22 个）
  - `packages/contracts/protocol/envelope.schema.json` + `protocol/frames/*.schema.json`（hello、welcome、ack、ping、agent.prompt、agent.output、agent.cancel、agent.clear、agent.status、approval.request、approval.decision、agents.sync、history.query、history.result、emergency.stop、emergency.resume、twin.capture、barrier.submit、error）
  - `packages/contracts/api/relay.openapi.json`、`api/node-local.openapi.json`（`x-permission`/`x-auth`/`x-errors` 扩展字段）
  - `packages/contracts/errors/error-codes.json`（28 个错误码 → httpStatus/retryable）、`identity/permissions.json`（36 个动作 × 3 角色矩阵）、`commands/im-commands.json`、`ux/ux-states.json`、`adapters/*.json`、`events/domain-events.json`、`resources/resources.json`
- 前置任务：TASK-001
- 前置状态：TASK-001 已合并（根 `package.json` 含 `contracts:gen`/`contracts:test` 委托脚本，workspace 含 `packages/*`）

## 4. 输出
- `packages/contracts/package.json`（`name: @workfleet/contracts`，`exports`：`./types`、`./validators`、`./errors`、`./permissions`、`./commands`、`./ux`、`./openapi`；scripts `contracts:gen`、`contracts:test`、`build`、`test`）
- `packages/contracts/scripts/gen.ts`（json-schema-to-typescript 生成类型；ajv 2020 standalone 代码生成校验器）、`packages/contracts/scripts/tsconfig.build.json`（allowedPaths 不含契约包根目录的 tsconfig，构建配置放 scripts/ 下）
- `packages/contracts/src/index.ts`、`src/errors.ts`（从 error-codes.json 导出 `ErrorCode` 联合类型与 `errorHttpStatus()`）、`src/permissions.ts`（导出 `Action`、`Role`、`isAllowed(role, action)`）、`src/envelope.ts`（`validateEnvelope()`，按 `type` 分派到帧校验器）
- `packages/contracts/generated/types/**`、`generated/validators/**`（提交入库，供漂移检查）
- `packages/contracts/test/schemas.test.ts`（元校验 + $ref 解析）、`test/examples.test.ts`（每个帧/实体至少 1 正例 1 反例）、`test/openapi.test.ts`（每个 operation 的 `x-errors` ⊆ error-codes、`x-permission` ∈ permissions.actions ∪ {public}）、`test/drift.test.ts`

## 5. Execution Steps
1. [ ] 读全部 52 个 schema，确认 `$id` 前缀 `https://workfleet.dev/contracts/v1/`；写 `scripts/gen.ts`：按 `$id` 注册到 ajv（Ajv2020 + ajv-formats），用 standalone 生成 ESM 校验器到 `generated/validators/`。
2. [ ] 用 json-schema-to-typescript（解析 `$ref` 至本地文件）生成 `generated/types/`，类型名取 schema `title` 的 PascalCase（如 `AgentPromptFrame`、`Conversation`）。
3. [ ] 写 `src/errors.ts`、`src/permissions.ts`、`src/envelope.ts`、`src/index.ts`；只做数据到类型/函数的薄映射，不引入任何业务逻辑。
4. [ ] 写 `test/schemas.test.ts`：所有 schema 通过 2020-12 元校验，全部 `$ref` 可解析。
5. [ ] 写 `test/examples.test.ts`：envelope 正例（`type: hello`，`seq: 0`）通过；反例（缺 `idempotencyKey`、`payload` 与 `type` 不匹配、ID 前缀错误如 `agt_` 用于 `conversationId`）失败；每个 entity 至少一正一反。
6. [ ] 写 `test/openapi.test.ts`：relay.openapi 每个 operation 的 `x-errors` 全在 `errors/error-codes.json`，`x-permission` 全在 `identity/permissions.json.actions` 或为 `public`；permissions.matrix 覆盖 actions×roles 全部 108 格。
7. [ ] 写 `test/drift.test.ts`（或在 `contracts:test` 中执行 `contracts:gen` 后 `git diff --exit-code -- packages/contracts/generated`）。
8. [ ] 执行 `pnpm contracts:gen && pnpm contracts:test`，结果写入证据目录；在完成记录中列出发现的契约缺陷（只报告，不改源文件）。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`pnpm contracts:gen && git diff --exit-code -- packages/contracts/generated` 退出码 0（无漂移）。
- [ ] AC-2：`pnpm contracts:test` 全部通过：52 个 schema 元校验通过、$ref 全可解析。
- [ ] AC-3：envelope 反例（缺 `idempotencyKey` / `type=agent.prompt` 但 payload 缺 `agentId` / `seq=-1`）均被 `validateEnvelope()` 拒绝；正例通过。
- [ ] AC-4：openapi 一致性：所有 `x-errors` ∈ error-codes（28 个），所有 `x-permission` ∈ permissions.actions ∪ {`public`}；矩阵 36×3 格无缺。
- [ ] AC-5：`import { validateEnvelope, isAllowed, ErrorCode } from '@workfleet/contracts'` 在 `apps/relay` 的 tsc 编译通过（用临时类型测试文件于 `packages/contracts/test/` 内模拟）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm install
pnpm contracts:gen
git diff --exit-code -- packages/contracts/generated
pnpm contracts:test
pnpm -F @workfleet/contracts typecheck
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-002/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `packages/contracts/package.json`
- `packages/contracts/scripts/**`
- `packages/contracts/src/**`
- `packages/contracts/generated/**`
- `packages/contracts/test/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-002/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/{api,errors,identity,protocol,schemas,adapters,commands,ux,resources,events}/**`（契约源文件本身；本卡只建构建/生成/测试设施，不改契约语义）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-002/` 除外）
- `apps/**`、`packages/testkit/**`

## 11. 依赖与阻塞
- Depends on：TASK-001
- Blocks：TASK-004, TASK-007, TASK-008, TASK-009, TASK-014
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 发现 schema 本身错误（如 required 字段不在 properties 中、$ref 指向不存在文件）→ 不修源文件，记录到证据 `contract-defects.md` 并 blocked 该条测试（`it.skip` + 缺陷编号），由主 Agent 发起契约变更任务
  - `packages/contracts/tsconfig.json` 不在 allowedPaths → 用 `scripts/tsconfig.build.json`；若工具链强制要求根 tsconfig 则 blocked
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：生成脚本与测试属机械工作，sonnect 足够；契约语义只读不改。

## 13. 升级条件
- 生成的类型与 schema 语义不一致（如 oneOf/null 处理导致类型丢失）且无法通过生成器选项修正 → 升 opus 评估生成策略
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING）：json-schema-to-typescript 对 2020-12 的 `$defs`/`oneOf` 支持足够；不足时以 ajv `JTDDataType` 或手写声明补充（证据不足/待实测）。
- 风险：`relay.openapi.json` 多个端点缺参数声明（如 `GET /api/v1/history/search` 无 q/displayId 参数、`GET /api/v1/stream` 无事件 schema）→ 本卡只报告，不补。
- 风险：生成物入库导致 PR 噪音 → 以漂移检查保证一致，CI 门禁由 TASK-014 接入。
- 本卡不涉及 U-02…U-08 平台未知项。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-002/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
