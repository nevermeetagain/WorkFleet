# TASK-005：identity+tenancy：注册/登录/登出/me、会话 Cookie+CSRF、权限拦截器（permissions.json）

```yaml
id: TASK-005
slice: S0
status: todo
owner: Agent-Relay
tier: opus
size: 大
title: "identity+tenancy：注册/登录/登出/me、会话 Cookie+CSRF、权限拦截器（permissions.json）"
dependsOn: ["003", "004"]
blocks: ["006", "061"]
reqs: "REQ-F-002/003"
allowedPaths: ["apps/relay/src/modules/identity/**", "apps/relay/src/modules/tenancy/**", "apps/relay/src/core/middleware/**", "apps/relay/tests/**/identity/**", "apps/relay/tests/**/tenancy/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-005/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S0
- 来源需求：REQ-F-002、REQ-F-003（tasks.v1.json 原值 `REQ-F-002/003`）
- 来源方案：ADR-006（HttpOnly 会话 Cookie + CSRF；RBAC 三角色 + 项目范围；`tenancy.assertPermission` 统一拦截）、ADR-012、architecture §4.1（identity/tenancy）

## 2. 目标
用户可注册（自动建 personal 组织 + admin 成员 + 默认项目）、登录、登出、查询 `/me`、切换组织；所有会话端点经统一权限拦截器按 `permissions.json` 判定，越权与跨组织访问按契约返回 403/404。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-006-鉴权与权限.md
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-002/003、§8（隐含前置）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.1
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`POST /api/v1/auth/register`（201 User；`VALIDATION_FAILED`、`CONFLICT`、`RATE_LIMITED`；password 12–128）、`POST /api/v1/auth/login`（200 `{user, tenants, csrf}`；`UNAUTHENTICATED`、`TOTP_REQUIRED`、`RATE_LIMITED`）、`POST /api/v1/auth/logout`、`GET /api/v1/me`（`{user, tenant, membership, permissions}`）、`POST /api/v1/me/switch-tenant`（`NOT_FOUND`）
  - `packages/contracts/identity/permissions.json`（matrix、extraRules、forbiddenPaths：跨 tenant→404 `NOT_FOUND`；viewer 非 GET→403 `FORBIDDEN`（`notification.subscribe` 除外）；设备令牌调 Web API→401 `UNAUTHENTICATED`）
  - `packages/contracts/identity/session-claims.schema.json`（sessionId、userId、tenantId、role、projectScope、csrf）
  - `packages/contracts/schemas/entities/{user,tenant,membership}.schema.json`；`errors/error-codes.json`（`UNAUTHENTICATED`、`FORBIDDEN`、`NOT_FOUND`、`IDEMPOTENCY_REPLAY`）
  - 表：`users`、`tenants`、`memberships`、`web_sessions`（`id_hash`、`csrf`）、`projects`（默认项目，depth=1）、`idempotency_keys`
- 前置任务：TASK-003、TASK-004
- 前置状态：TASK-003（core/db、仓储基类、`openTestDatabase`）与 TASK-004（bootstrap、错误映射、模块自动注册）已合并

## 4. 输出
- `apps/relay/src/modules/identity/{domain,application,interfaces/http,infrastructure}/**`、`index.ts`（公开 `authenticate()`、`currentPrincipal()`）
- `apps/relay/src/modules/tenancy/{domain,application,interfaces,infrastructure}/**`、`index.ts`（公开 `assertPermission(principal, action, resource?)`、`createPersonalTenant()`）
- `apps/relay/src/core/middleware/{session.ts,csrf.ts,permission.ts,idempotency.ts,rate-limit.ts}`：按路由 `x-permission`/`x-auth` 元数据自动挂载
- 测试：`apps/relay/tests/unit/modules/identity/**`、`apps/relay/tests/unit/modules/tenancy/**`、`apps/relay/tests/integration/modules/identity/**`、`apps/relay/tests/integration/modules/tenancy/permission-matrix.test.ts`

## 5. Execution Steps
1. [ ] identity 领域：Email/Password 值对象；argon2id 哈希；会话 ID 256-bit 随机，库内只存 SHA-256（`web_sessions.id_hash`）；Cookie `wf_sid`：HttpOnly、Secure（生产）、SameSite=Lax、Path=/。
2. [ ] 注册用例：单事务内建 `users`、`tenants(kind=personal)`、`memberships(role=admin)`，并建默认项目（`projects` depth=1，slug `default`，供 S0 步行骨架使用）；邮箱重复→`CONFLICT`。
3. [ ] 登录/登出/me/switch-tenant 用例：登录成功返回 `csrf`（同存 `web_sessions.csrf`）；`me.permissions` = 当前角色在 matrix 中为 true 的动作列表；切换到无成员关系的 tenant→`NOT_FOUND`。
4. [ ] 中间件：`session.ts` 解析 Cookie→principal（不接受 `Authorization: Bearer` 设备令牌，命中则 401 `UNAUTHENTICATED`）；`csrf.ts` 对非 GET 校验 `X-CSRF-Token`；`idempotency.ts` 以 `(principal, Idempotency-Key)` 读写 `idempotency_keys`，重放返回首次结果；`rate-limit.ts` 对 register/login 限速→`RATE_LIMITED`（带 `retryAfterSec`）。
5. [ ] `permission.ts` + `tenancy.assertPermission`：读 `@workfleet/contracts` 的 permissions；规则顺序：跨 tenant→404 `NOT_FOUND` → viewer 非 GET→403 → matrix → extraRules（`device.ownerUserId`）→ projectScope 非空时限制项目类资源。
6. [ ] 写权限矩阵契约测试：遍历 36 动作 × 3 角色共 108 格，以内置探针路由（测试内注册，`x-permission` 取各动作）断言 200/403。
7. [ ] 写集成测试：注册→登录→me→登出全流程；两个组织用户互访对方资源返回 404（不泄露存在性）；无 CSRF 的 POST→403 `FORBIDDEN`。
8. [ ] 执行第 7 节命令并保存证据。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：集成测试：`POST /auth/register`→201，`POST /auth/login`→200 且 `Set-Cookie: wf_sid=…; HttpOnly`，`GET /me`→200 且 `permissions` 与 permissions.json 中 admin 列一致，`POST /auth/logout` 后 `GET /me`→401 `UNAUTHENTICATED`。
- [ ] AC-2：权限矩阵测试 108 格全部与 `identity/permissions.json` 一致（REQ-F-003）。
- [ ] AC-3：跨组织访问返回 404 `NOT_FOUND`、viewer 调非 GET 返回 403 `FORBIDDEN`、`Authorization: Bearer <设备令牌>` 调 Web API 返回 401 `UNAUTHENTICATED`（forbiddenPaths 三条）。
- [ ] AC-4：`web_sessions` 中无明文会话 ID；`users.password_hash` 以 `$argon2id$` 开头。
- [ ] AC-5：同一 `Idempotency-Key` 重复提交返回首次响应（状态码与体一致），`idempotency_keys` 只有 1 行。
- [ ] AC-6：注册后 `projects` 存在该 tenant 的 depth=1 默认项目。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/relay test tests/unit/modules/identity tests/unit/modules/tenancy
pnpm -F @workfleet/relay test tests/integration/modules/identity tests/integration/modules/tenancy
pnpm -F @workfleet/relay typecheck
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-005/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/relay/src/modules/identity/**`
- `apps/relay/src/modules/tenancy/**`
- `apps/relay/src/core/middleware/**`
- `apps/relay/tests/**/identity/**`
- `apps/relay/tests/**/tenancy/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-005/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-005/` 除外）
- `apps/relay/src/modules/projects/**`（项目模块归 TASK-061；本卡仅经 tenancy 仓储写默认项目行，不建 projects 模块目录）
- `apps/relay/src/modules/devices/**`、`node-gateway/**`（TASK-006）
- `apps/relay/src/core/**` 中除 `core/middleware/**` 外的目录（TASK-003/004）

## 11. 依赖与阻塞
- Depends on：TASK-003, TASK-004
- Blocks：TASK-006, TASK-061
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 主 Agent 不同意在注册时由 tenancy 写入默认项目（`projects` 表归 projects 模块语义）→ S0 无可用项目，TASK-006/010/013 将无法建智能体/会话 → blocked 等裁定
  - REQ-F-002 写“越权返回 403 FORBIDDEN”，而 permissions.json forbiddenPaths 写“跨 tenant 返回 404 NOT_FOUND” → 本卡按契约（404）实现，冲突已报告；若裁定改为 403 需改契约
  - TOTP（可选能力）登录分支：契约有 `TOTP_REQUIRED` 但无 TOTP 设置端点 → 本卡只实现“未开启 TOTP”路径，开启分支留空并登记
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
opus　理由：鉴权与权限拦截是安全边界，越权缺陷代价高（不可逆的数据泄露），按 opus 执行。

## 13. 升级条件
- 本卡已为 opus：若需推翻 ADR-006（如改为 JWT）或修改 permissions.json → 升 fable 并 blocked
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
大　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-08）：v1 不做第三方登录（ADR-006 backlog）。
- 风险：契约与需求对跨组织状态码不一致（403 vs 404），已报告；测试以契约为准。
- 风险：项目范围（projectScope）判断依赖资源的 projectId 解析，各模块需在路由元数据提供 `resolveProjectId`——本卡定义接口，具体解析由各模块实现。
- 本卡不涉及 U-02…U-07 平台未知项。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-005/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
