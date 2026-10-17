# TASK-061：projects：主/子项目树、深度≤3、overview 汇总

```yaml
id: TASK-061
slice: S3
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Relay
tier: sonnect
size: 中
title: "projects：主/子项目树、深度≤3、overview 汇总"
dependsOn: ["005"]
blocks: ["065", "141"]
reqs: "REQ-F-004"
allowedPaths: ["apps/relay/src/modules/projects/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S3（可演示：两台电脑、个人+公司两个中转、主/子项目树；同目录第二个写入者被拒或分到 worktree）
- 来源需求：REQ-F-004
- 来源方案：ADR-003（存储）、ADR-006（鉴权与权限）、ADR-012（全局命名与格式）；architecture §4.1 `projects` 模块

## 2. 目标
中转 `projects` 模块实现项目一级对象的增改查与主/子项目树（深度 ≤3、禁止成环、移动时整棵子树重算深度）以及 `GET /api/v1/projects/{projectId}/overview` 子树汇总，且越租户访问返回 404。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §4.1（projects 职责、公开 API `getProjectTree()`）、§7 数据归属
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-004-项目一级对象与主-子项目.md`
  - `docs/WorkFleet-V0.0.4/00_governance/glossary.md`（项目 project、组织 tenant）
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/projects`（扁平列表含 parentId）、`POST /api/v1/projects`（x-errors: VALIDATION_FAILED, CONFLICT；Idempotency-Key + X-CSRF-Token 必填）、`PATCH /api/v1/projects/{projectId}`（改名/归档/移动）、`GET /api/v1/projects/{projectId}/overview`（nodes[].{projectId,unread,running,pendingApprovals}）
  - `packages/contracts/schemas/entities/project.schema.json`（depth 1–3、slug `^[a-z0-9][a-z0-9-]{0,47}$`、parentId 可空）
  - `packages/contracts/identity/permissions.json`：`project.read`（三角色）、`project.write`（admin/operator）；`$comment` 中 membership.projectScope 范围规则；forbiddenPaths 跨 tenant → 404 NOT_FOUND
  - `packages/contracts/errors/error-codes.json`：VALIDATION_FAILED、CONFLICT（version 不匹配）、NOT_FOUND、FORBIDDEN、IDEMPOTENCY_REPLAY
  - `database/migrations/relay/0001_init.sql`：表 `projects`（CHECK depth BETWEEN 1 AND 3、`ux_projects_slug`、`ix_projects_parent`、version 乐观锁）；汇总读取 `agents.status`、`approvals.status='pending'`、`conversations`/`messages`
- 前置任务：TASK-005
- 前置状态：TASK-005 已合并（会话鉴权与 `assertPermission`）；TASK-003 仓储基类可用；迁移 0001 已应用

## 4. 输出
- `apps/relay/src/modules/projects/domain/`：Project 实体、深度/成环/子树移动规则（纯函数）
- `apps/relay/src/modules/projects/application/`：create/update/move/archive/list/overview 用例
- `apps/relay/src/modules/projects/infrastructure/persistence/`：projects 仓储（Kysely，递归 CTE 取子树）
- `apps/relay/src/modules/projects/interfaces/http/`：4 个端点的路由与 schema 校验（用 contracts 生成的 ajv 校验器）
- `apps/relay/src/modules/projects/index.ts`：公开 `getProjectTree()`、`assertProjectInScope()`
- `apps/relay/src/modules/projects/__tests__/`：单测与 HTTP 集成测试
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-061/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 读 project.schema.json 与 projects 表，列出字段映射（is archived→archived、version→乐观锁），写入实现备注到证据 README。
2. [ ] domain 层实现规则：新建深度 = 父深度+1，>3 抛 VALIDATION_FAILED（details.fields[parentId]）；移动时校验“新父不在自身子树内”（防环）且“子树最大深度 + 偏移 ≤3”。
3. [ ] infrastructure 层实现仓储：按 tenant_id 过滤所有查询；子树用 `WITH RECURSIVE`；更新带 `WHERE version=?`，0 行 → CONFLICT。
4. [ ] application 层实现用例，移动操作在单事务内批量更新子树 depth；slug 冲突映射 CONFLICT（ux_projects_slug）。
5. [ ] 实现 overview：对子树每个节点汇总 running（agents.status='running'）、pendingApprovals（approvals.status='pending' 经 conversations.project_id 关联）；unread 见阻塞条件。
6. [ ] interfaces/http 挂载路由：权限 project.read/project.write；projectScope 非空时限制到范围内项目；跨 tenant 一律 404。
7. [ ] 在 index.ts 只导出公开 API，不导出仓储；跑 `make guard` 确认无跨模块深层引用。
8. [ ] 补齐测试：深度边界（3 可建、4 拒绝）、成环移动拒绝、并发 PATCH 版本冲突、跨租户 404、viewer 写 403、overview 计数；输出写入证据。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] `POST /api/v1/projects` 在第 4 层返回 400 VALIDATION_FAILED；第 3 层成功且响应通过 project.schema.json 校验
- [ ] 把项目移到自己的子孙下返回 400 VALIDATION_FAILED；合法移动后整棵子树 depth 正确（单测断言）
- [ ] 两个并发 PATCH 同一 version，第二个返回 409 CONFLICT
- [ ] 租户 A 用户读取租户 B 的项目/overview 返回 404 NOT_FOUND；viewer 调 POST 返回 403 FORBIDDEN
- [ ] overview 的 running、pendingApprovals 与种子数据一致，响应通过契约 schema 校验
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过

## 7. 验证命令
```bash
pnpm --filter @workfleet/relay exec vitest run src/modules/projects
pnpm --filter @workfleet/relay exec tsc --noEmit
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/relay/src/modules/projects/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-061/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-061/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `apps/relay/src/modules/projects/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-061/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/relay/src/modules/tenancy/**、identity/**（TASK-005/141 所有）
- 其他 `apps/relay/src/modules/*` 目录

## 11. 依赖与阻塞
- Depends on：TASK-005
- Blocks：TASK-065, TASK-141
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - overview 的 `unread` 在迁移 0001 中没有已读游标表/字段可计算：先按“未读 = 0 并在响应注释中标注”还是阻塞，需规划 Agent 裁决；未裁决前标 blocked（只阻塞 unread，不阻塞其余部分合并须经裁决）
  - TASK-005 未提供 `assertPermission`/projectScope 读取能力
  - 需要新增错误码（如项目深度专用码）才能表达失败路径

## 12. 建议执行档位
sonnect　理由：单模块 CRUD + 树规则，规则明确、契约与表已冻结，适合主力档。

## 13. 升级条件
- unread 口径需要新增表或契约字段 → 升 opus 出 ADR
- 移动子树与 projectScope 交互出现安全歧义（可见性泄露）→ 升 opus 安全审查
- 连续 2 次验收失败 → 按熔断规则重写任务书

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- 无 U-xx 直接关联；与 U-08（工期）相关：overview unread 口径若需新表会拖延 S3。
- 假设：项目删除只做归档（archived=1），v1 不提供硬删除端点（契约无 DELETE）。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - Agent-Contract/Agent-Data：overview.unread 缺少已读状态的数据来源（无 read_markers 类表），需补契约说明或迁移 0002
  - Agent-Contract：`GET /projects/{id}/overview` 的 x-errors 为空，应至少含 NOT_FOUND/FORBIDDEN

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-061/
- 验证者结论：
- 遗留问题 / 跟进项编号：
