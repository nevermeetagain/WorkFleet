# TASK-104：Web：模式选择、屏障配置与状态

```yaml
id: TASK-104
slice: S5
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-App
tier: sonnect
size: 中
title: "Web：模式选择、屏障配置与状态"
dependsOn: ["065", "103"]
blocks: ["105", "145"]
reqs: "REQ-F-016/021"
allowedPaths: ["apps/web/src/features/routes/modes/**", "apps/web/src/features/barriers/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S5（可演示：场景 2——三个来源汇总后分别发给老板与数据部；通知模式两人回话分会话）
- 来源需求：REQ-F-016/021
- 来源方案：ADR-008、ADR-006；DEC-006；architecture §6.3

## 2. 目标
中转控制台的绑定编辑器支持选择通知/团队模式并即时显示模式约束错误，提供汇总屏障的配置表单与状态列表（open/complete/timed_out，缺失来源可见）。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §6.3
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-016-绑定与三种模式.md`、`REQ-F-021-汇总屏障.md`
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`POST/PATCH /api/v1/routes`（ROUTE_INVALID）、`POST /api/v1/routes/dry-run`、`GET/POST /api/v1/barriers`
  - `packages/contracts/schemas/entities/route.schema.json`（mode）、`barrier.schema.json`
  - `packages/contracts/errors/error-codes.json`：ROUTE_INVALID（ui“dry-run 面板显示原因”）、VALIDATION_FAILED
  - `packages/contracts/ux/ux-states.json`：`route_editor_dry_run`、`route_list` × 六态（无独立 barrier 界面）
  - `packages/contracts/identity/permissions.json`：route.write、route.dry_run、route.read
- 前置任务：TASK-065, TASK-103
- 前置状态：TASK-065 已合并；TASK-103 屏障端点可用；TASK-046 绑定编辑器提供模式选择插槽

## 4. 输出
- `apps/web/src/features/routes/modes/`：模式选择器（management/notification/team）、各模式说明与即时校验提示、dry-run 结果中的模式解释
- `apps/web/src/features/barriers/`：屏障创建表单（来源多选 ≥2、超时 10–86400 秒）、屏障列表与状态徽标（含缺失来源）、hooks/api
- 各目录 `*.test.tsx`
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-104/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 在 features/routes/modes 实现模式选择器并通过 TASK-046 编辑器插槽挂载；切换模式时前端预校验基数约束（与 TASK-102 口径一致的说明文案）。
2. [ ] 提交时以服务端为准：ROUTE_INVALID 的 details 显示在 dry-run 面板（ui 列要求）。
3. [ ] notification 模式在目标选择器中对微信接收人显示“不可群发”说明（DEC-046）；team 模式显示“入站只到一个目标”。
4. [ ] 在 features/barriers 实现创建表单：只允许 team/notification 绑定；来源从绑定 sources 中多选且 ≥2；超时范围 10–86400。
5. [ ] 实现屏障列表：轮询 `GET /barriers`（契约无推送事件），status 徽标；timed_out 时显示缺失来源（expectedSources − received）。
6. [ ] 为 route_editor_dry_run、route_list 补齐六态；屏障列表复用 route_list 六态约定。
7. [ ] 组件测试：模式切换、ROUTE_INVALID 展示、来源少于 2 禁止提交、timed_out 显示缺失来源、viewer 只读。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 选择 notification 并加入他人微信接收人，提交后 dry-run 面板显示 ROUTE_INVALID 原因（组件测试 mock 422）
- [ ] 屏障表单在来源 <2 或超时越界时不可提交
- [ ] timed_out 屏障行显示缺失来源别名
- [ ] viewer 角色看不到创建与编辑入口；六态可用 data-ux-state 断言
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过

## 7. 验证命令
```bash
pnpm --filter @workfleet/web exec vitest run src/features/routes/modes src/features/barriers
pnpm --filter @workfleet/web exec tsc --noEmit
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/web/src/features/routes/modes/|apps/web/src/features/barriers/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-104/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-104/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `apps/web/src/features/routes/modes/**`
- `apps/web/src/features/barriers/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-104/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/web/src/features/routes/** 中 modes/ 以外部分、apps/web/src/pages/routes/**（TASK-046）
- apps/web/src/i18n/**、components/**、data-access/**（TASK-009）

## 11. 依赖与阻塞
- Depends on：TASK-065, TASK-103
- Blocks：TASK-105, TASK-145
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 本任务无任何 pages/** 路径：若 TASK-046 的绑定页没有可挂载模式选择器与屏障列表的插槽，停止并请求规划扩大路径
  - 新增文案无法写入 i18n/**（同 TASK-065）
  - 屏障状态需要实时推送但 `/api/v1/stream` 未定义 barrier 事件 → 先用轮询，若验收要求实时则 blocked

## 12. 建议执行档位
sonnect　理由：表单与列表组件，后端口径已由 TASK-102/103 确定。

## 13. 升级条件
- 前后端约束口径不一致 → 升 opus 与 TASK-102 执行者仲裁
- 需要新增页面路由 → 规划变更

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- 无 U-xx 直接关联。
- 假设：屏障列表轮询间隔 5 s，满足演示（推断）。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - 规划：TASK-104 allowedPaths 不含 pages/**，屏障 UI 的挂载点依赖 TASK-046
  - Agent-Contract：ux-states 无 barrier 界面；stream 通道未定义 barrier 状态事件

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-104/
- 验证者结论：
- 遗留问题 / 跟进项编号：
