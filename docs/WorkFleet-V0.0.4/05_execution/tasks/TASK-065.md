# TASK-065：Web：项目树、设备页、跨项目视图

```yaml
id: TASK-065
slice: S3
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-App
tier: sonnect
size: 中
title: "Web：项目树、设备页、跨项目视图"
dependsOn: ["046", "061", "062"]
blocks: ["067", "104"]
reqs: "REQ-F-004/005"
allowedPaths: ["apps/web/src/pages/projects/**", "apps/web/src/features/projects/**", "apps/web/src/features/devices/primary/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S3（可演示：两台电脑、个人+公司两个中转、主/子项目树；同目录第二个写入者被拒或分到 worktree）
- 来源需求：REQ-F-004/005
- 来源方案：ADR-008（前端）、ADR-006；architecture §3 apps/web relay 目标；DEC-057

## 2. 目标
中转控制台提供项目树页（主/子项目增改、移动、归档）、跨项目视图（子树未读/运行中/待审批汇总）与设备页上的“设为主设备”，每个界面实现 ux-states 六态。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §3（apps/web relay 目标）、§5（前端依赖方向 pages → features → components/ui → lib）
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-004-项目一级对象与主-子项目.md`、`REQ-F-005-一个账号多台设备.md`
  - `docs/WorkFleet-V0.0.4/02_requirements/non-functional/REQ-NF-011-可用性与语言.md`（zh-CN、文案集中 i18n）
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`GET/POST /api/v1/projects`、`PATCH /api/v1/projects/{projectId}`、`GET /api/v1/projects/{projectId}/overview`、`GET /api/v1/devices`、`POST /api/v1/devices/{deviceId}/primary`
  - `packages/contracts/schemas/entities/project.schema.json`、`device.schema.json`
  - `packages/contracts/ux/ux-states.json`：screens `project_tree`、`device_list` × 六态，断言属性 `data-ux-state`
  - `packages/contracts/errors/error-codes.json`：VALIDATION_FAILED、CONFLICT、FORBIDDEN、NOT_FOUND、DEVICE_REVOKED 的 ui 列
  - `packages/contracts/identity/permissions.json`：project.write、device.set_primary（viewer 只读）
- 前置任务：TASK-046, TASK-061, TASK-062
- 前置状态：TASK-046 Web 渠道/绑定页已合并（data-access 与路由约定稳定）；TASK-061、TASK-062 后端端点可用

## 4. 输出
- `apps/web/src/pages/projects/`：项目树页、跨项目视图页（只做组合）
- `apps/web/src/features/projects/`：树组件、创建/改名/移动/归档表单、overview 汇总、hooks 与 api（经 data-access）
- `apps/web/src/features/devices/primary/`：设为主设备按钮与确认对话框
- 各目录内 `*.test.tsx` 组件测试
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-065/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 对照 ux-states.json 列出 project_tree、device_list 的六态与触发条件，写入证据 README。
2. [ ] 在 features/projects 实现 api hooks：所有写请求带 Idempotency-Key 与 X-CSRF-Token；错误按 error-codes ui 列展示。
3. [ ] 实现树组件：按 parentId 组装；深度到 3 时禁用“新建子项目”；拖拽/选择移动时前端预校验成环与深度，后端 400 仍以字段错误展示。
4. [ ] 实现跨项目视图：调用 overview，节点上展示 未读/运行中/待审批 徽标，可展开子树。
5. [ ] 实现 features/devices/primary：仅 device.set_primary 权限可见；切换后列表就地更新、Toast 2.5 s；revoked 设备禁用。
6. [ ] pages/projects 组合 features，挂载六态（data-ux-state），无权限时展示 no_permission 页不显示数据。
7. [ ] 写组件测试（mock data-access）：六态渲染、深度禁用、409 CONFLICT 刷新、viewer 无写按钮。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] project_tree 与 device_list 的六态都能通过 `[data-ux-state=...]` 断言（组件测试）
- [ ] 深度 3 的节点“新建子项目”按钮禁用；后端返回 VALIDATION_FAILED 时字段下方显示 details 文案
- [ ] viewer 角色看不到任何写按钮；FORBIDDEN 时显示 no_permission 页
- [ ] “设为主设备”成功后同一 owner 只有一台显示“主设备”标识
- [ ] `pnpm --filter @workfleet/web exec tsc --noEmit` 与 `make guard`（pages→features 方向）通过；越界检查只输出 SCOPE OK

## 7. 验证命令
```bash
pnpm --filter @workfleet/web exec vitest run src/pages/projects src/features/projects src/features/devices/primary
pnpm --filter @workfleet/web exec tsc --noEmit
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/web/src/pages/projects/|apps/web/src/features/projects/|apps/web/src/features/devices/primary/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-065/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-065/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `apps/web/src/pages/projects/**`
- `apps/web/src/features/projects/**`
- `apps/web/src/features/devices/primary/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-065/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/web/src/features/devices/** 中 primary/ 以外部分（TASK-009）
- apps/web/src/i18n/**、apps/web/src/components/**、apps/web/src/data-access/**（TASK-009 所有）
- apps/web/src/features/routes/**

## 11. 依赖与阻塞
- Depends on：TASK-046, TASK-061, TASK-062
- Blocks：TASK-067, TASK-104
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 新增文案需要写入 `apps/web/src/i18n/**`（REQ-NF-011 要求集中），但不在 allowedPaths：若 TASK-009 未提供按 feature 命名空间注册文案的机制，停止并请求规划
  - 设备页（pages/devices，TASK-009 所有）没有可挂载 primary 按钮的插槽
  - overview.unread 由后端标注为不可用（见 TASK-061 跟进项）

## 12. 建议执行档位
sonnect　理由：常规页面与组件，契约与 UX 状态已冻结，主力档即可。

## 13. 升级条件
- 需要改 data-access 或全局路由 → 升 opus 协调 TASK-009 所有者
- 跨项目视图性能不达 REQ-NF-011（4G 首屏 ≤3 s）需要后端改分页 → 升 opus

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- 无 U-xx 直接关联；U-08（工期）影响 S3 演示顺序。
- 假设：项目移动交互用“选择新父项目”对话框而非拖拽（推断，减少可访问性风险）。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - 规划：065/066/104 均需新增 zh-CN 文案但无 i18n/** 写权限
  - Agent-Contract：ux-states 无“跨项目视图”独立界面，本任务复用 project_tree 六态

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-065/
- 验证者结论：
- 遗留问题 / 跟进项编号：
