# TASK-013：步行骨架 E2E：注册→配对→发消息→收到回声（Playwright + 真中转 + 真节点 + FakeAgent）

```yaml
id: TASK-013
slice: S0
status: todo
owner: Agent-QA
tier: sonnect
size: 中
title: "步行骨架 E2E：注册→配对→发消息→收到回声（Playwright + 真中转 + 真节点 + FakeAgent）"
dependsOn: ["011", "012"]
blocks: []
reqs: "REQ-F-015"
allowedPaths: ["tests/e2e/**", "playwright.config.ts"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-013/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S0
- 来源需求：REQ-F-015（tasks.v1.json 原值 `REQ-F-015`）
- 来源方案：slices.md S0 演示脚本（注册 → 配对码 → 节点配对上线 → Web 发消息 → FakeAgent 回声）、ADR-011（E2E 只在 ubuntu）、architecture §3（E2E 中转端口 5110–5119）

## 2. 目标
一条 Playwright 用例在真中转 + 真节点 + FakeAgent 下自动完成：注册 → 生成配对码 → 节点 `pair`+`start` → 设备显示在线 → 新建与 `echo` 智能体的会话 → 发送 `hello` → 10 s 内看到 `echo: hello`。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/04_planning/slices.md S0
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §3（端口段）
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-015、REQ-F-001
- 契约：
  - `packages/contracts/ux/ux-states.json`（`data-ux-state` 断言：`device_list` success、`chat` success）
  - `packages/contracts/api/relay.openapi.json`：`POST /api/v1/auth/register`、`POST /api/v1/devices/pairing-codes`、`POST /api/v1/devices/claim`、`GET /api/v1/node-gateway`、`POST /api/v1/conversations`、`POST /api/v1/conversations/{conversationId}/messages`、`GET /api/v1/stream`、`GET /api/v1/health`（webServer 就绪探测）
  - `packages/contracts/protocol/frames/{hello,welcome,agent.prompt,agent.output}.schema.json`（链路经过的帧）
- 前置任务：TASK-011、TASK-012
- 前置状态：TASK-011（节点回声）与 TASK-012（聊天页）已合并，间接要求 TASK-005/006/007/009/010 已合并；中转支持 `WF_RELAY_DEV_SEED_ECHO=1`，节点支持 `WF_NODE_ECHO_MODE=1`

## 4. 输出
- `playwright.config.ts`（projects 按切片目录 `tests/e2e/s0` …；`webServer`：中转 `pnpm -F @workfleet/relay start`（`WF_RELAY_PORT=5110`、临时数据目录、`WF_RELAY_DEV_SEED_ECHO=1`、`WF_RELAY_PUBLIC_URL=http://127.0.0.1:5110`）与 Web `pnpm -F @workfleet/web preview --port 5112`（代理到 5110）；`retries: 0`；trace on-first-retry）
- `tests/e2e/support/{ports.ts,relay.ts,node.ts,fixtures.ts}`（节点子进程：`pnpm -F @workfleet/node cli pair …` 与 `start`，`WF_NODE_ECHO_MODE=1`、`WF_NODE_CONSOLE_PORT=5113`、临时数据目录，结束时清理）
- `tests/e2e/s0/walking-skeleton.spec.ts`

## 5. Execution Steps
1. [ ] 写 `playwright.config.ts` 与 `tests/e2e/support/ports.ts`（E2E 端口固定在 5110–5119：中转 5110、Web 5112、节点控制台 5113），并以 `/api/v1/health` 作为中转就绪探测。
2. [ ] 写 `support/node.ts`：封装配对与启动节点子进程、等待 `GET http://127.0.0.1:5113/local/v1/status` 显示 relay-link `connected`、teardown 杀进程树并删除临时目录。
3. [ ] 写 `support/fixtures.ts`：每个用例随机邮箱注册新账号，保证可重复运行。
4. [ ] 写 `walking-skeleton.spec.ts`：注册→登录→配对页读取 8 位码→`node.pair(code)`+`node.start()`→设备列表 `data-ux-state=success` 且该设备“在线”。
5. [ ] 继续：进入聊天→新建会话选 `echo`→输入 `hello` 发送→断言 10 s 内出现文本 `echo: hello` 的气泡，且刷新页面后历史仍在（账本持久化）。
6. [ ] 失败时保存 trace、截图、中转与节点日志到证据目录；本地连续运行 3 次确认稳定。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`pnpm e2e tests/e2e/s0` 在 ubuntu 上通过，连续 3 次运行全部 PASS（无 retries）。
- [ ] AC-2：用例中节点经 `workfleet-node pair` 用 UI 显示的配对码成功配对，设备列表显示“在线”。
- [ ] AC-3：发送 `hello` 后 10 s 内出现 `echo: hello`；刷新页面后两条消息仍在。
- [ ] AC-4：用例结束后无残留节点进程与临时目录（teardown 断言）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。 E2E：`pnpm e2e <目录>` = `playwright test <目录>`；`make e2e` 跑全部。
```bash
pnpm exec playwright install --with-deps chromium
pnpm e2e tests/e2e/s0
for i in 1 2 3; do pnpm e2e tests/e2e/s0 || exit 1; done
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-013/
- `test-output.txt`：3 次运行输出
- `playwright-report/`：HTML 报告
- `logs/`：中转与节点日志（失败时）
- `summary.md`：AC 结论

## 9. 允许修改
- `tests/e2e/**`
- `playwright.config.ts`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-013/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-013/` 除外）
- `tests/e2e/s1/**`、`tests/e2e/s2/**` 等其他切片目录（归 TASK-030/048 等）
- `apps/**`（发现产品缺陷时只记录并退回对应任务，不在本卡修代码）
- `packages/**`

## 11. 依赖与阻塞
- Depends on：TASK-011, TASK-012
- Blocks：—
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 中转未提供 Web 静态资源托管（无任务负责在 relay 托管 apps/web 构建产物）→ 本卡用 `vite preview` 代理；若需同源部署形态则 blocked 交主 Agent 分配
  - `relay-link.schema.json` 要求 `wss://`，E2E 中转为 `ws://127.0.0.1:5110` → 依赖 TASK-007 的测试放行开关；缺失则 blocked
  - S0 无“默认项目 + echo 智能体”的正式创建路径 → 依赖 TASK-005/006 的权宜实现；缺失则 blocked
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：E2E 脚本编写属主力档工作，失败时只记录不修产品代码，sonnect 足够。

## 13. 升级条件
- 用例在 CI 上连续 2 次不稳定（同代码时过时不过）→ 升 opus 做跨模块时序排查
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-08）：E2E 只在 ubuntu 运行（ADR-011），三平台节点安装在 TASK-209/210。
- 风险：端口 5110–5113 被占用导致假失败 → `ports.ts` 启动前探测并给出明确报错。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-013/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
