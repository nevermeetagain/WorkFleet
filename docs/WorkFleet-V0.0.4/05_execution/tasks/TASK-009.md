# TASK-009：Web 骨架：路由、登录/注册/配对/设备列表页、data-access、UX 状态组件

```yaml
id: TASK-009
slice: S0
status: todo
owner: Agent-App
tier: sonnect
size: 大
title: "Web 骨架：路由、登录/注册/配对/设备列表页、data-access、UX 状态组件"
dependsOn: ["002"]
blocks: ["012"]
reqs: "REQ-F-015"
allowedPaths: ["apps/web/src/app/**", "apps/web/src/pages/auth/**", "apps/web/src/pages/devices/**", "apps/web/src/features/auth/**", "apps/web/src/features/devices/**", "apps/web/src/components/**", "apps/web/src/data-access/**", "apps/web/src/lib/**", "apps/web/src/styles/**", "apps/web/src/i18n/**", "apps/web/vite.config.ts", "apps/web/index.html"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-009/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S0
- 来源需求：REQ-F-015（tasks.v1.json 原值 `REQ-F-015`）
- 来源方案：ADR-008（React 19 + Vite + TanStack Query + Zustand + Radix/shadcn + Tailwind 4；一份 SPA 两个构建目标）、ADR-006（Cookie + CSRF）、DESIGN-001（文档未落地）、PROJECT-STRUCTURE-SPEC §10（前端分层）

## 2. 目标
Web 控制台骨架可构建并运行：登录、注册、配对码生成、设备列表四个页面可用；data-access 统一处理 CSRF、Idempotency-Key 与错误码；四个界面均实现 ux-states.json 规定的 6 种状态并以 `data-ux-state` 暴露。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-008-前端.md、ADR-006-鉴权与权限.md
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §3（apps/web 两个构建目标）、§5（pages→features→components→lib）
  - docs/项目完整目录结构.txt §10.2、§11（前端归属速查）
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-015、REQ-NF-011（zh-CN、i18n）
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`POST /api/v1/auth/register`、`POST /api/v1/auth/login`（返回 `csrf`）、`POST /api/v1/auth/logout`、`GET /api/v1/me`（`permissions[]`）、`POST /api/v1/devices/pairing-codes`（`X-CSRF-Token`）、`GET /api/v1/devices`、`POST /api/v1/devices/{deviceId}/revoke`
  - `packages/contracts/ux/ux-states.json`：screens `login`、`register`、`device_pairing`、`device_list` × states `empty/loading/error/no_permission/success/offline`；`dataAttribute: data-ux-state`；loading 骨架 ≥200 ms 才显示
  - `packages/contracts/errors/error-codes.json`（`ui` 列文案映射；`UNAUTHENTICATED`→跳转登录、`FORBIDDEN`→no_permission、`RATE_LIMITED`→含 retryAfterSec 的 Toast、`PAIRING_CODE_INVALID`）、`schemas/common/error.schema.json`
  - `packages/contracts/schemas/entities/{user,tenant,membership,device}.schema.json`（经 `@workfleet/contracts` 生成类型）
- 前置任务：TASK-002
- 前置状态：TASK-002 已合并；联调需 TASK-005/006（开发期可用 MSW 风格的本地假响应，测试不依赖中转）

## 4. 输出
- `apps/web/index.html`（入口指向 `/src/app/main.tsx`——`src/main.tsx` 不在 allowedPaths，偏离 §10.2 已登记）、`apps/web/vite.config.ts`（`mode relay|node`；dev 代理 `/api` 与 `/api/v1/stream`（ws）→ `127.0.0.1:5101`；`test` 段 jsdom + `src/lib/test/setup.ts`）
- `apps/web/src/app/{main.tsx,App.tsx,router.tsx,providers.tsx,query-client.ts}`：`router.tsx` 以 `import.meta.glob('../pages/*/routes.tsx', {eager:true})` 自动收集页面路由（后续页面任务无需改 app/）
- `apps/web/src/pages/auth/{routes.tsx,LoginPage.tsx,RegisterPage.tsx}`、`apps/web/src/pages/devices/{routes.tsx,DeviceListPage.tsx,PairDevicePage.tsx}`
- `apps/web/src/features/auth/**`（login/register/logout/me hooks、`useCan(action)` 基于 `/me.permissions`）、`apps/web/src/features/devices/**`（列表、配对码、吊销）
- `apps/web/src/components/{ui,layout,ux-state}/**`（`<UxState screen state>` 统一渲染 6 态，含 traceId 复制与 retryable 重试）
- `apps/web/src/data-access/{client.ts,errors.ts,endpoints.ts,websocket.ts}`（fetch 封装：`credentials:'include'`、非 GET 自动带 `X-CSRF-Token`（来自登录响应/`me`）与 `Idempotency-Key`（ULID）；错误体经 `error.schema.json` 解析为 `ApiError{code,traceId,retryable}`）
- `apps/web/src/lib/**`、`apps/web/src/styles/**`（Tailwind 4 CSS-first）、`apps/web/src/i18n/{index.ts,locales/zh-CN.json,locales/en-US.json}`
- 组件/特性测试与源码同目录 `*.test.tsx`（前端规范 §10.2 允许就近测试）

## 5. Execution Steps
1. [ ] 搭 `vite.config.ts`、`index.html`、`app/` 五件套；`router.tsx` 实现页面路由自动收集与登录守卫（`GET /me` 401 → `/login?next=`）。
2. [ ] 实现 `data-access/client.ts`：统一请求、CSRF、Idempotency-Key、错误解析；`UNAUTHENTICATED` 触发全局登出跳转；`RATE_LIMITED` 读取 `details.retryAfterSec`。
3. [ ] 实现 `components/ux-state`：严格按 ux-states.json 文案语义；loading 延迟 200 ms 显示骨架；error 显示错误码 `ui` 文案 + traceId 复制 + 可重试按钮；容器节点挂 `data-ux-state=<state>`。
4. [ ] 实现 `features/auth` 与 `pages/auth`：注册（password 12–128 前端校验与服务端 `VALIDATION_FAILED.details.fields[]` 回填）、登录、登出。
5. [ ] 实现 `features/devices` 与 `pages/devices`：配对页调用 `POST /devices/pairing-codes`，显示 8 位码、10 分钟倒计时与命令 `workfleet-node pair --relay <当前源> --code <码>`；列表页显示名称/OS/版本/在线状态/最后在线时间；吊销按钮仅 `useCan('device.revoke')` 时显示。
6. [ ] i18n：所有界面文案进 `locales/zh-CN.json`（en-US 先占位），组件内不硬编码中文（REQ-NF-011）。
7. [ ] 写测试：data-access CSRF/Idempotency 头注入；`<UxState>` 6 态渲染与 `data-ux-state`；登录失败显示 `UNAUTHENTICATED` 文案；viewer（无 `device.pair`）进入配对页呈 `no_permission`。
8. [ ] 执行第 7 节命令（含 `build` 与 `build:node` 不报错）并保存证据与截图。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`pnpm -F @workfleet/web test` 全绿；`pnpm -F @workfleet/web build` 与 `build:node` 退出码 0。
- [ ] AC-2：4 个 screen（login/register/device_pairing/device_list）各 6 种状态均有组件测试，断言容器 `data-ux-state` 值正确。
- [ ] AC-3：非 GET 请求均带 `X-CSRF-Token` 与 `Idempotency-Key` 头（单测拦截 fetch 断言）；错误响应解析出 `code` 与 `traceId`。
- [ ] AC-4：`me.permissions` 不含 `device.pair` 时配对页渲染 `no_permission`；不含 `device.revoke` 时列表无吊销按钮。
- [ ] AC-5：源码中无硬编码中文界面文案（`grep -rP '[\x{4e00}-\x{9fa5}]' apps/web/src --include=*.tsx` 仅命中测试与注释，脚本断言）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/web test
pnpm -F @workfleet/web typecheck
pnpm -F @workfleet/web build && pnpm -F @workfleet/web build:node
grep -rlP '[\x{4e00}-\x{9fa5}]' apps/web/src --include=*.tsx | grep -v '\.test\.tsx$' && echo "HARDCODED zh TEXT" || echo "i18n ok"
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-009/
- `test-output.txt`：第 7 节命令输出
- `screenshots/`：4 个页面各状态截图（Vite dev + 本地假响应）
- `summary.md`：AC 逐条结论

## 9. 允许修改
- `apps/web/src/app/**`
- `apps/web/src/pages/auth/**`
- `apps/web/src/pages/devices/**`
- `apps/web/src/features/auth/**`
- `apps/web/src/features/devices/**`
- `apps/web/src/components/**`
- `apps/web/src/data-access/**`
- `apps/web/src/lib/**`
- `apps/web/src/styles/**`
- `apps/web/src/i18n/**`
- `apps/web/vite.config.ts`
- `apps/web/index.html`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-009/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-009/` 除外）
- `apps/web/src/pages/{chat,agents,history,approvals,channels,routes,projects,members,audit}/**` 与对应 `features/**`（归 TASK-012/027/029/046/065/145）
- `apps/web/src/targets/**`（TASK-066/165）
- `apps/web/package.json`、`apps/web/tsconfig.json`（TASK-001）
- `apps/relay/**`、`apps/node/**`

## 11. 依赖与阻塞
- Depends on：TASK-002
- Blocks：TASK-012
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - `apps/web/src/main.tsx`、`src/types/**`、`src/constants/**`、`src/stores/**` 均不在任何任务 allowedPaths → 本卡把入口放 `src/app/main.tsx`、全局类型/常量放 `src/lib/`；若主 Agent 要求严格按 §10.2 则 blocked 等补 allowedPaths
  - `GET /api/v1/stream` 的事件 schema 在契约中缺失 → 本卡只提供 `data-access/websocket.ts` 的通用重连客户端，不定义事件类型
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：页面与组件是标准 CRUD 前端工作，sonnect 主力档适用。

## 13. 升级条件
- 需要改变 ADR-008 选型（如换路由/状态库）→ 升 opus
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
大　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-07）：PWA 与 Web Push 不在本卡（TASK-204），iOS 行为待实测。
- 风险：DESIGN-001（前端设计）文档未落地，视觉规范缺失 → 按 shadcn 默认 + Tailwind 4 实现，后续统一换肤。
- 风险：页面路由自动收集约定若被否决，后续每个页面任务都需改 `app/router.tsx`（跨所有权）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-009/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
