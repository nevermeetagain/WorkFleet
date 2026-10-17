# TASK-141：成员、邀请、项目范围（projectScope）

```yaml
id: TASK-141
slice: S7
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Relay
tier: sonnect
size: 中
title: "成员、邀请、项目范围（projectScope）"
dependsOn: ["061"]
blocks: ["145"]
reqs: "REQ-F-003"
allowedPaths: ["apps/relay/src/modules/tenancy/application/invitations/**", "apps/relay/src/modules/tenancy/application/scope/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S7
- 来源需求：REQ-F-003
- 来源方案：ADR-006（RBAC 三角色 + 项目范围）；DEC-047（多用户与角色）；architecture §4.1 tenancy

## 2. 目标
admin 可邀请成员（一次性链接，指定角色与 projectScope）、被邀请人接受后成为成员；`projectScope` 非空的成员对 project/agent/route/conversation 类动作只能作用于范围内项目，越界返回 404 `NOT_FOUND`，由集成测试逐条证明。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-006-鉴权与权限.md
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-002/003）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.1
  - docs/WorkFleet-V0.0.4/00_governance/glossary.md（成员/角色/项目）
  - docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md（DEC-047）
- 契约：
  - packages/contracts/api/relay.openapi.json：`GET /api/v1/members`（tenant.read）、`POST /api/v1/members/invitations`（member.invite，Idempotency-Key）、`PATCH /api/v1/members/{membershipId}`（member.update_role，body 含 `version`）、`DELETE /api/v1/members/{membershipId}`（member.remove）
  - packages/contracts/schemas/entities/membership.schema.json（`projectScope` 空数组 = 全部项目）；identity/role.schema.json
  - packages/contracts/identity/permissions.json：`$comment` 项目范围规则、`forbiddenPaths[0]` 跨组织 404、`member.*` 三格
  - packages/contracts/errors/error-codes.json：`FORBIDDEN`、`NOT_FOUND`、`CONFLICT`（version 不匹配）、`VALIDATION_FAILED`、`IDEMPOTENCY_REPLAY`
  - database/migrations/relay/0001_init.sql：表 `memberships`（`project_scope`、`version`）、`invitations`（`token_hash`、`expires_at`、`accepted_at`）、`projects`
- 前置任务：TASK-061
- 前置状态：TASK-005 的 `tenancy.assertPermission` 与会话 Cookie+CSRF 已合并；TASK-061 项目树 API 已合并。

## 4. 输出
- apps/relay/src/modules/tenancy/application/invitations/（create-invitation、accept-invitation、revoke-expired 用例；令牌 256 bit 随机，库内只存 SHA-256）
- apps/relay/src/modules/tenancy/application/scope/（`resolveProjectScope(principal)`、`assertInScope(principal, projectId)`、`scopeFilter()` 查询谓词；含子项目继承规则）
- 上述两目录内的 `__tests__/*.test.ts`（单测 + 基于 SQLite 内存库的集成测试）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-141/`（见 §8）

## 5. Execution Steps
1. [ ] 读 permissions.json 的 `$comment` 与 membership.schema.json，在 EVD 写一页“范围语义”说明：scope 中的项目是否包含其子项目（默认包含整棵子树，推断）、空数组=全部。
2. [ ] 实现 `scope/`：`resolveProjectScope` 从 `memberships.project_scope` 读出并展开子树；`assertInScope` 越界时抛 `NOT_FOUND`（不泄露存在性，与跨组织规则一致）；导出 Kysely 谓词供列表查询使用。
3. [ ] 实现 `invitations/` 创建：校验邀请人 `member.invite`、`projectScope` 中项目均属本组织，生成一次性令牌（只存 `token_hash`），返回 `inviteUrl`/`expiresAt`（默认 7 天，推断，写入 EVD）；同一 Idempotency-Key 重放返回首次结果。
4. [ ] 实现接受邀请用例：令牌过期/已用 → `VALIDATION_FAILED`；已是成员 → `CONFLICT`；成功则写 `memberships`（角色与 scope 来自邀请）并置 `accepted_at`。
5. [ ] 实现改角色/范围用例：乐观锁 `version` 不匹配 → `CONFLICT`；禁止把组织最后一个 admin 降级或移除（返回 `CONFLICT`，推断规则，写入 EVD）。
6. [ ] 导出 `registerInvitationRoutes()` / scope 中间件工厂供 tenancy 接口层挂载（接口层不在本卡允许路径内，见阻塞条件）。
7. [ ] 写测试：三角色 × member.* 端点矩阵；scope=[A] 的 operator 访问 B 的 agent/route/conversation → 404；scope 含父项目时可访问子项目；跨组织 → 404。
8. [ ] 运行验证命令，把输出与范围语义说明存入 EVD-141。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] `member.invite/update_role/remove` 对 admin 通过、对 operator/viewer 返回 403 `FORBIDDEN`（自动化矩阵测试）。
- [ ] 邀请令牌库内仅存 SHA-256；过期或重复使用被拒；Idempotency-Key 重放返回首次响应（测试覆盖）。
- [ ] `projectScope=[prj_A]` 的成员对 prj_B 下 agent/route/conversation 的读写全部返回 404 `NOT_FOUND`，对 prj_A 子项目可访问（测试覆盖）。
- [ ] PATCH 带过期 `version` 返回 409 `CONFLICT`；最后一个 admin 不可被降级/移除。
- [ ] `make guard` 通过（只经 tenancy 公开 API 被其他模块使用）。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-141/
pnpm --filter ./apps/relay exec vitest run src/modules/tenancy/application/invitations src/modules/tenancy/application/scope --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-141/vitest.txt
pnpm --filter ./apps/relay exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-141/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-141/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-141/
- `vitest.txt`、`tsc.txt`、`guard.txt`
- `scope-semantics.md`（子树继承、空数组、最后 admin 规则、邀请有效期的取值与依据标签）

## 9. 允许修改
- `apps/relay/src/modules/tenancy/application/invitations/**`
- `apps/relay/src/modules/tenancy/application/scope/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-141/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-141/` 除外，见 ownership-matrix §4）
- apps/relay/src/modules/tenancy/ 下除 application/invitations、application/scope 外的文件（TASK-005 所有）
- apps/relay/src/modules/projects/**（TASK-061）
- apps/relay/src/core/middleware/**

## 11. 依赖与阻塞
- Depends on：TASK-061
- Blocks：TASK-145
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 契约无“接受邀请”端点（在已扫描的 relay.openapi.json 范围内未找到 `/invitations/{token}/accept` 类路径）：用例可实现，但对外暴露需契约补充 → 接口挂载部分标 blocked，报主 Agent 走契约变更。
  - membership.schema.json 无 `version` 字段而 PATCH 请求体要求 `version`：若生成类型导致无法返回 version，标 blocked 报契约缺陷。
  - tenancy 接口层（interfaces/http）不在允许路径：若 TASK-005 未提供按目录自动注册路由的机制，挂载需改 TASK-005 文件 → blocked。

## 12. 建议执行档位
sonnect　理由：规则已由 ADR-006 与 permissions.json 定死，属 CRUD + 谓词实现，可逆且影响面限于 tenancy。

## 13. 升级条件
- 需要改变范围语义（如 scope 不继承子树）或权限矩阵解释 → opus（安全语义）。
- 发现 TASK-005 的 assertPermission 不支持 scope 注入 → opus 仲裁跨模块接口。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否　邀请 + 范围两个子域，各约半天。

## 15. 风险与假设
- 假设：scope 包含子项目（推断，DEC-047 未明说）。
- 假设：邀请有效期 7 天、单次使用（推断）。
- 风险：列表接口若漏用 `scopeFilter` 会泄露数据 → TASK-146 越权矩阵复查。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-141/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-141.md`）
