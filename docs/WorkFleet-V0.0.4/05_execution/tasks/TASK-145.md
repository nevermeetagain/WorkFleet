# TASK-145：Web：成员、过滤规则、审计、投递；本机分身页

```yaml
id: TASK-145
slice: S7
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-App
tier: sonnect
size: 大
title: "Web：成员、过滤规则、审计、投递；本机分身页"
dependsOn: ["104", "141", "142", "143", "144"]
blocks: ["146"]
reqs: "REQ-F-003/027/028/029"
allowedPaths: ["apps/web/src/pages/members/**", "apps/web/src/features/members/**", "apps/web/src/features/filters/**", "apps/web/src/pages/audit/**", "apps/web/src/features/audit/**", "apps/web/src/targets/node/twin/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S7
- 来源需求：REQ-F-003 / REQ-F-027 / REQ-F-028 / REQ-F-029
- 来源方案：ADR-008（前端栈）；DEC-047；契约 ⑥ UX States

## 2. 目标
在中转控制台提供成员（邀请/改角色与范围/移除）、过滤规则（CRUD + 预览）、审计与投递（查询、死信重放）界面，在本机控制台提供分身数据页（查看/修改/删除/导出）；每个页面实现 ux-states.json 规定的 6 种状态并以 `data-ux-state` 可断言。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-008-前端.md
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-003/027/028/029、REQ-NF-005/011）
  - docs/WorkFleet-V0.0.4/00_governance/glossary.md
- 契约：
  - packages/contracts/ux/ux-states.json：screens `members`、`filter_rules`、`audit_log`、`node_local_twin`（各 6 态；`dataAttribute: data-ux-state`）
  - packages/contracts/api/relay.openapi.json：members 4 端点、filter-rules 4 端点、`/api/v1/routes/dry-run`、`/api/v1/audit`、`/api/v1/deliveries`、`/api/v1/deliveries/{deliveryId}/replay`、`/api/v1/me`（权限列表）
  - packages/contracts/api/node-local.openapi.json：`/local/v1/twin/events`、`/local/v1/twin/events/{twinEventId}`、`/local/v1/twin/export`
  - packages/contracts/errors/error-codes.json：`FORBIDDEN`→no_permission、`CONFLICT`→Toast 刷新、`RATE_LIMITED`
  - packages/contracts/identity/permissions.json（按钮可见性：filter.write 仅 admin，audit.read 无 operator）
- 前置任务：TASK-104, TASK-141, TASK-142, TASK-143, TASK-144
- 前置状态：TASK-104/141/142/143/144 已合并；TASK-009 的 data-access 与 UX 状态组件、TASK-066 的 node 构建目标已可用。

## 4. 输出
- apps/web/src/pages/members/、apps/web/src/features/members/（成员列表、邀请对话框、角色/范围编辑、移除确认）
- apps/web/src/features/filters/（规则列表、编辑表单、按接收人预览——调用 dry-run）
- apps/web/src/pages/audit/、apps/web/src/features/audit/（审计列表、投递明细含死信筛选与重放）
- apps/web/src/targets/node/twin/（分身事件列表、行内编辑、删除、导出 JSONL 下载、“分身数据只在本机”说明）
- 各目录 `__tests__/*.test.tsx`（vitest + Testing Library + MSW）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-145/`（见 §8）

## 5. Execution Steps
1. [ ] 从 `@workfleet/contracts` 生成类型建 data-access hooks（TanStack Query）；禁止手写 DTO。
2. [ ] 成员页：列表、邀请（角色 + 项目范围多选，显示一次性链接）、改角色/范围（带 `version`，409 时 Toast 并刷新）、移除；按 `/me` 权限隐藏无权按钮。
3. [ ] 过滤规则：CRUD 表单（action、fields、maskStyle、match.recipientIds/businessLines）+ “按接收人预览”调用 `/routes/dry-run` 并并排显示各接收人可见内容；非 admin 只读。
4. [ ] 审计页：审计列表（cursor 分页）+ 投递明细（status 标签、filtersApplied、lastError），死信行“重放”按钮（202 后行内刷新）。
5. [ ] 本机分身页：列表、行内编辑 text、删除确认、导出下载；页头固定说明“分身数据只保存在本机节点”。
6. [ ] 四个 screen 均实现 empty/loading/error/no_permission/success/offline 并加 `data-ux-state`；文案全部进 `apps/web/src/i18n`（若该目录不在本卡允许路径则就近放 feature 内 `messages.ts` 并报缺陷）。
7. [ ] 写组件测试：每 screen × 6 态快照/断言；viewer 访问成员写操作 → no_permission；死信重放调用正确端点。
8. [ ] 运行验证命令并存证（含 4 个 screen 的截图）。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 4 个 screen × 6 种 UX 状态均可通过 `[data-ux-state=…]` 断言（组件测试 24 组通过）。
- [ ] viewer 登录时成员/过滤写操作不可见，直接调用得到 no_permission 态（测试覆盖）。
- [ ] 过滤预览对同一样例消息显示 ≥2 个接收人的不同可见字段（MSW 夹具测试）。
- [ ] 死信重放按钮发出 `POST /api/v1/deliveries/{id}/replay` 并就地更新行状态。
- [ ] 分身页导出得到 `.jsonl` 文件，删除后列表不再显示该条（测试覆盖）。
- [ ] `pnpm --filter ./apps/web build` 两个构建目标均成功；`make guard` 通过。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-145/
pnpm --filter ./apps/web exec vitest run src/pages/members src/features/members src/features/filters src/pages/audit src/features/audit src/targets/node/twin --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-145/vitest.txt
pnpm --filter ./apps/web build | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-145/build.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-145/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-145/
- `vitest.txt`、`build.txt`、`guard.txt`
- `screenshots/`（members、filter_rules、audit_log、node_local_twin 各至少 success 与 no_permission 两张）

## 9. 允许修改
- `apps/web/src/pages/members/**`
- `apps/web/src/features/members/**`
- `apps/web/src/features/filters/**`
- `apps/web/src/pages/audit/**`
- `apps/web/src/features/audit/**`
- `apps/web/src/targets/node/twin/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-145/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-145/` 除外，见 ownership-matrix §4）
- apps/web/src/app/**、apps/web/src/components/**、apps/web/src/i18n/**（不在本卡允许路径）
- apps/web/src/targets/node/ 下除 twin/ 外目录

## 11. 依赖与阻塞
- Depends on：TASK-104, TASK-141, TASK-142, TASK-143, TASK-144
- Blocks：TASK-146
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 过滤规则无对应 `pages/filters/**` 允许路径：默认作为成员页内“权限与过滤”标签页挂载；若需独立路由需改 `app/**` → 报主 Agent。
  - 新页面的路由注册在 `apps/web/src/app/**`（不在允许路径）：若 TASK-009 未采用 pages 目录自动发现，标 blocked。
  - i18n 资源目录不在允许路径，与 REQ-NF-011“文案集中在 i18n 资源”冲突 → 报规划缺陷。

## 12. 建议执行档位
sonnect　理由：纯前端组件与 CRUD 页面，契约与 UX 状态已定，可逆。

## 13. 升级条件
- 无。若发现契约字段不足以渲染（如审计无过滤参数导致不可用）→ 报缺陷，不升级。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
大　是否小于 2 小时：否　4 个 screen，约 2 天。

## 15. 风险与假设
- 审计列表无服务端过滤（契约缺陷，见 TASK-143），先做客户端当前页过滤。
- 分身页属 node 构建目标，鉴权为本机 `x-auth: local`。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-145/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-145.md`）
