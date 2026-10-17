# TASK-004：中转启动层：Fastify、core（config/logging/errors 映射 error-codes）、/health

```yaml
id: TASK-004
slice: S0
status: todo
owner: Agent-Relay
tier: sonnect
size: 小
title: "中转启动层：Fastify、core（config/logging/errors 映射 error-codes）、/health"
dependsOn: ["002"]
blocks: ["005"]
reqs: "REQ-F-002"
allowedPaths: ["apps/relay/src/bootstrap/**", "apps/relay/src/core/** (除 core/db)", "apps/relay/src/modules/system/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-004/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S0
- 来源需求：REQ-F-002（tasks.v1.json 原值 `REQ-F-002`）
- 来源方案：ADR-009（Fastify 5 + pino + ajv）、ADR-002（错误码唯一源）、architecture §3（5101 内部监听）/§4.3（core）/§5（依赖方向）

## 2. 目标
中转进程可启动并监听 127.0.0.1:5101，提供 `GET /api/v1/health`；所有错误按 `error.schema.json` 统一格式输出并携带 traceId；模块按约定自动注册，后续模块任务无需改 bootstrap。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §3、§4.1（system 模块）、§4.3、§5
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-009-后端运行栈.md、ADR-012-全局命名与格式.md
  - docs/项目完整目录结构.txt §8.1–8.2（bootstrap/core/modules 分层）
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/health`（响应 `{status: ok|degraded, version, db}`，`x-auth: none`）
  - `packages/contracts/schemas/common/error.schema.json`（`{error:{code,message,details?,traceId,retryable}}`）
  - `packages/contracts/errors/error-codes.json`（`VALIDATION_FAILED`→400、`NOT_FOUND`→404、`PAYLOAD_TOO_LARGE`→413、`INTERNAL`→500 等 28 码的 httpStatus/retryable）
  - `packages/contracts/schemas/common/ids.schema.json#/$defs/traceId`（`trc_` + ULID）
- 前置任务：TASK-002
- 前置状态：TASK-002 已合并（`@workfleet/contracts` 导出 `ErrorCode`、`errorHttpStatus()`、校验器）；TASK-003 若已合并则 health 接入 DB 探针，否则使用注入的假探针

## 4. 输出
- `apps/relay/src/bootstrap/{main.ts,app.ts,container.ts,module-loader.ts}`：`module-loader` 扫描 `src/modules/*/index.ts`，调用其导出的 `register(app, ctx)`（约定写在 `module-loader.ts` 头注释中）
- `apps/relay/src/core/config/**`（读取 `WF_RELAY_PORT`、`WF_RELAY_DATA_DIR`、`WF_RELAY_MASTER_KEY_FILE`、`WF_RELAY_PUBLIC_URL`、`WF_LOG_LEVEL`，ajv 校验，默认端口 5101、仅绑 127.0.0.1）
- `apps/relay/src/core/logging/**`（pino；每请求生成/透传 `traceId`，响应头 `X-Trace-Id`）
- `apps/relay/src/core/errors/**`（`AppError(code, message, details)`；Fastify `setErrorHandler` 映射 httpStatus/retryable；schema 校验失败→`VALIDATION_FAILED` + `details.fields[]`；body >1 MiB→`PAYLOAD_TOO_LARGE`）
- `apps/relay/src/modules/system/{index.ts,interfaces/http/health.routes.ts,application/get-health.ts,domain/ports/db-probe.ts}`
- 测试：`apps/relay/tests/unit/core/**`（不含 db）、`apps/relay/tests/integration/modules/system/**`

## 5. Execution Steps
1. [ ] 实现 `core/config`：env → 类型化配置，非法值启动即失败并打印字段名（不打印值）。
2. [ ] 实现 `core/logging`：pino 实例 + Fastify 钩子，`traceId` 取请求头 `X-Trace-Id`（合法时）否则新生成 `trc_`+ULID。
3. [ ] 实现 `core/errors`：从 `@workfleet/contracts` 读取码表；未知异常→`INTERNAL`（500，retryable=true），响应体严格符合 `error.schema.json`（用 ajv 校验器在测试中断言）。
4. [ ] 实现 `bootstrap/app.ts`（工厂，便于测试 `app.inject`）、`main.ts`（监听 `127.0.0.1:${WF_RELAY_PORT}`，SIGTERM 优雅关闭）、`module-loader.ts`（按目录名字母序加载各模块 `register`，模块缺 `register` 时跳过并告警）。
5. [ ] 实现 `modules/system`：`GET /api/v1/health` 返回 `{status, version, db}`；`db` 通过 `DbProbe` 端口获得（TASK-003 已合并时用 `core/db` 的 `SELECT 1`，否则返回 `"unknown"` 且 `status: degraded`）。
6. [ ] 写测试：health 200 且响应过 openapi 响应 schema；未注册路由→404 `NOT_FOUND` 格式正确；故意抛错路由（测试内注册）→500 `INTERNAL` 带 traceId；超 1 MiB 请求→413 `PAYLOAD_TOO_LARGE`。
7. [ ] 执行第 7 节命令，保存证据（含 `curl` 输出）。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`GET /api/v1/health` 返回 200，响应体通过 relay.openapi 对应响应 schema 校验。
- [ ] AC-2：任意错误响应体通过 `error.schema.json` 校验，且 HTTP 状态 = error-codes.json 中该码的 `httpStatus`（覆盖 `NOT_FOUND`/`VALIDATION_FAILED`/`PAYLOAD_TOO_LARGE`/`INTERNAL` 四码）。
- [ ] AC-3：每个响应带 `X-Trace-Id`，与错误体 `error.traceId` 一致且匹配 `^trc_[0-9A-HJKMNP-TV-Z]{26}$`。
- [ ] AC-4：进程只监听 127.0.0.1（`ss -ltnp | grep 5101` 显示 127.0.0.1:5101）（REQ-NF-004）。
- [ ] AC-5：在 `src/modules/` 下新增仅含 `index.ts`（导出 `register`）的测试模块即可被加载，无需修改 bootstrap（测试用临时目录注入 loader 根路径验证）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/relay test tests/unit/core tests/integration/modules/system
pnpm -F @workfleet/relay typecheck
WF_RELAY_PORT=5101 WF_RELAY_DATA_DIR=$(mktemp -d) pnpm -F @workfleet/relay start & sleep 3
curl -si http://127.0.0.1:5101/api/v1/health; curl -si http://127.0.0.1:5101/api/v1/nope; kill %1
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-004/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/relay/src/bootstrap/**`
- `apps/relay/src/core/** (除 core/db)`
- `apps/relay/src/modules/system/**`
- 明确写出的测试目录（本模块专属；allowedPaths 未含测试路径，按任务指令 §3 在此显式声明，执行前须经主 Agent 确认）：
  - `apps/relay/tests/unit/core/**（不含 core/db）`
  - `apps/relay/tests/integration/modules/system/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-004/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-004/` 除外）
- `apps/relay/src/core/db/**`（TASK-003）
- `apps/relay/src/core/middleware/**`（会话/CSRF/权限/幂等中间件归 TASK-005；本卡不建该目录）
- `apps/relay/src/modules/**`（除 `modules/system/**`）
- `apps/node/**`、`apps/web/**`

## 11. 依赖与阻塞
- Depends on：TASK-002
- Blocks：TASK-005
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 模块自动注册约定若被主 Agent 否决（需改为显式注册）→ 后续每个模块任务都需改 bootstrap（跨所有权）→ blocked 等待裁定
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：Fastify 启动层与错误映射是成熟样板，sonnect 足够；模块注册约定已在本卡写死。

## 13. 升级条件
- 错误映射需引入契约外的新错误码 → 升 opus 并 blocked
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
小　是否小于 2 小时：否

## 15. 风险与假设
- 假设：health 的 DB 探针在 TASK-003 合并前以假探针返回 `degraded`——本卡不依赖 TASK-003（依赖图未声明），合并顺序由 DAG W2→W3 保证大概率先有 core/db。
- 风险：`core/**` 与 TASK-005 的 `core/middleware/**` 路径重叠 → 本卡不创建 middleware 目录，避免冲突。
- 本卡不涉及 U-02…U-08。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-004/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
