# TASK-066：本机控制台（node 构建目标）：中转连接、适配器探测、诊断页

```yaml
id: TASK-066
slice: S3
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-App
tier: sonnect
size: 中
title: "本机控制台（node 构建目标）：中转连接、适配器探测、诊断页"
dependsOn: ["063"]
blocks: ["067", "165"]
reqs: "REQ-F-006"
allowedPaths: ["apps/web/src/targets/node/**", "apps/web/src/features/local-*/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S3（可演示：两台电脑、个人+公司两个中转、主/子项目树；同目录第二个写入者被拒或分到 worktree）
- 来源需求：REQ-F-006
- 来源方案：ADR-008（同一 SPA 两种构建目标）、ADR-001；architecture §3 apps/web node 目标、§4.2 local-console

## 2. 目标
`apps/web` 的 node 构建目标提供本机控制台：中转连接管理（列表/新增/删除）、本机智能体适配器探测结果、诊断页，只访问 127.0.0.1:5100 的本机 API。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §3（apps/web node 目标：本机工具、模型配置、Key、诊断；端口 5100）、§4.2 local-console
  - `docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-008-前端.md`
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-006-多中转连接.md`
- 契约：
  - `packages/contracts/api/node-local.openapi.json`：`GET /local/v1/status`、`GET/POST /local/v1/relay-links`、`DELETE /local/v1/relay-links/{relayLinkId}`、`GET /local/v1/adapters/detect`、`GET /local/v1/doctor`（x-auth: local）
  - `packages/contracts/schemas/entities/relay-link.schema.json`
  - `packages/contracts/adapters/input-adapters.v1.json`（展示 displayName、experimental、docsUrl）
  - `packages/contracts/ux/ux-states.json`：screens `node_local_agents`、`node_local_doctor` × 六态
  - `packages/contracts/errors/error-codes.json`：PAIRING_CODE_INVALID、CONFLICT、DEVICE_REVOKED、PROTOCOL_VERSION_UNSUPPORTED、AGENT_UNAVAILABLE
- 前置任务：TASK-063
- 前置状态：TASK-063 已合并（relay-links 本机 API 可用）；TASK-009 已提供 node 构建目标入口（vite 配置）

## 4. 输出
- `apps/web/src/targets/node/`：node 目标的路由壳、导航（中转连接 / 智能体 / 诊断）
- `apps/web/src/features/local-relay-links/`：列表、新增（url + 8 位配对码 + label）、删除确认
- `apps/web/src/features/local-adapters/`：探测结果表（已安装/版本/缺失 + 文档链接，实验项标注）
- `apps/web/src/features/local-diagnostics/`：status + doctor 汇总
- 各目录 `*.test.tsx`
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-066/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 确认 TASK-009 的 vite 配置能以 `--mode node` 或等价方式产出 node 目标；只在 targets/node 内注册路由。
2. [ ] 实现 local-relay-links：表单校验 url 以 wss:// 开头、配对码 8 位；错误码按 ui 列展示；删除需二次确认并说明“该中转下的智能体会被移除”。
3. [ ] 实现 local-adapters：调用 adapters/detect，与 input-adapters.v1.json 合并显示；experimental 项显示“实验”徽标；缺失项链接 docsUrl。
4. [ ] 实现 local-diagnostics：展示 status（版本、各中转连接状态、智能体数、资源占用）；doctor 端点不可用时显示 empty 态说明“诊断项由后续版本提供”。
5. [ ] 为 node_local_agents、node_local_doctor 两个界面实现六态 data-ux-state；中转连接页复用同一六态约定。
6. [ ] 写组件测试：新增连接成功/配对码错误/重复连接 409；探测结果合并；doctor 404 降级显示。
7. [ ] 构建 node 目标并确认产物不引用中转 API（grep `/api/v1/` 为 0）。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] node 目标构建成功，产物中 grep 不到 `/api/v1/` 调用
- [ ] 新增中转：配对码错误显示 PAIRING_CODE_INVALID 字段错误；重复 url+tenant 显示 CONFLICT Toast（组件测试）
- [ ] 适配器探测页显示已安装/未安装与版本，实验项有徽标
- [ ] node_local_agents、node_local_doctor 六态均可用 `[data-ux-state]` 断言
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过

## 7. 验证命令
```bash
pnpm --filter @workfleet/web exec vitest run src/targets/node src/features/local-
pnpm --filter @workfleet/web exec vite build --mode node
grep -rl "/api/v1/" apps/web/dist-node || echo "NO RELAY API IN NODE TARGET"
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/web/src/targets/node/|apps/web/src/features/local-[^/]*/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-066/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-066/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `apps/web/src/targets/node/**`
- `apps/web/src/features/local-*/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-066/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/web/src/targets/node/models/**、supervisor/**、twin/**（TASK-165/144 后续写入）
- apps/web/vite.config.ts、apps/web/src/i18n/**（TASK-009）
- apps/node/**

## 11. 依赖与阻塞
- Depends on：TASK-063
- Blocks：TASK-067, TASK-165
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - TASK-009 未提供 node 构建目标（vite 配置不在本任务路径内）
  - `GET /local/v1/doctor` 尚未实现（doctor 属 S10）：按降级态交付，不阻塞；若验收方要求真实 doctor 结果则 blocked
  - 本机 API 的 `x-auth: local` 鉴权方式（同源 Cookie/本机令牌）在契约中未说明，前端无法确定如何带凭据

## 12. 建议执行档位
sonnect　理由：页面组合与表单，契约已给出端点，风险低。

## 13. 升级条件
- 需要定义本机 API 鉴权方式 → 升 opus 与 Agent-Node 协商并出 ADR
- 需要在 node 目标内显示任何中转数据 → 升 opus（违反数据归属）

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- 与 U-05 相关：探测结果的版本号格式依赖各智能体 `--version` 输出，未实测。
- 假设：`dist-node` 为 node 目标的产物目录名（推断，以 TASK-009 为准）。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - Agent-Contract：ux-states 无本机“中转连接”界面（node_local_relay_links），本任务复用六态约定
  - Agent-Contract：node-local.openapi 的 `x-auth: local` 语义未定义；`/local/v1/status`、`/adapters/detect` 响应为无结构 object

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-066/
- 验证者结论：
- 遗留问题 / 跟进项编号：
