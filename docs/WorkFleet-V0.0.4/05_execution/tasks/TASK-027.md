# TASK-027：Web：智能体列表/表单（rjsf 按 configSchema）、聊天指令、历史页

```yaml
id: TASK-027
slice: S1
status: todo
owner: Agent-App
tier: sonnect
size: 大
title: "Web：智能体列表/表单（rjsf 按 configSchema）、聊天指令、历史页"
dependsOn: ["012", "026"]
blocks: ["029", "046"]
reqs: "REQ-F-007/018/019"
allowedPaths: ["apps/web/src/pages/agents/**", "apps/web/src/features/agents/**", "apps/web/src/pages/history/**", "apps/web/src/features/history/**", "apps/web/src/features/chat/commands/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-027/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S1
- 来源需求：REQ-F-007、REQ-F-018、REQ-F-019（tasks.v1.json 原值 `REQ-F-007/018/019`）
- 来源方案：ADR-008（表单用 @rjsf 按适配器 JSON Schema 渲染，DEC-010）、REQ-F-007/018/019、ux-states.json

## 2. 目标
Web 增加智能体列表与表单（按 `configSchema` 由 rjsf 渲染）、聊天输入框的指令补全与 system 消息呈现、历史检索页；三个界面实现对应 UX 6 态。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-008-前端.md
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-007、REQ-F-018、REQ-F-019
  - docs/项目完整目录结构.txt §10.2
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/agents`、`POST /api/v1/agents`（`ALIAS_TAKEN`、`DEVICE_OFFLINE`、`VALIDATION_FAILED`）、`PATCH/DELETE /api/v1/agents/{agentId}`、`GET /api/v1/adapters/input`、`GET /api/v1/history/search`（q / displayId / nativeSessionId / includeAgentTranscript）、`GET /api/v1/devices`
  - `packages/contracts/adapters/input-adapter-spec.schema.json`（`configSchema` 作为 rjsf schema；`experimental` 显示“实验”徽标）
  - `packages/contracts/commands/im-commands.json`（补全候选：syntax、args、desc、permission，按 `/me.permissions` 过滤）
  - `packages/contracts/ux/ux-states.json` screens `agent_list`、`agent_form`、`conversation_history`；`errors/error-codes.json`（`ALIAS_TAKEN` 字段错误）
- 前置任务：TASK-012、TASK-026
- 前置状态：TASK-012（聊天页、Composer）与 TASK-026（agents-registry API）已合并；TASK-025 合并后历史页联调

## 4. 输出
- `apps/web/src/pages/agents/{routes.tsx,AgentListPage.tsx,AgentFormPage.tsx}`、`apps/web/src/features/agents/**`（列表：alias、适配器、设备、项目、状态、实验徽标；表单：选适配器→rjsf 渲染 configSchema；alias 正则 `^[a-z][a-z0-9_-]{0,31}$` 前端校验）
- `apps/web/src/features/chat/commands/**`（`CommandSuggest` 补全浮层、`SystemMessage` 渲染；由 Composer 经 features/chat 暴露的扩展点挂载）
- `apps/web/src/pages/history/{routes.tsx,HistoryPage.tsx}`、`apps/web/src/features/history/**`（三种查询方式切换、两端记录并排：左 IM/Web 账本，右智能体转录；离线时转录区显示 offline 态）
- 同目录测试 `*.test.tsx`

## 5. Execution Steps
1. [ ] `features/agents/api` + 列表页：分页、按设备/项目过滤（参数按 TASK-026 实现）、状态徽标；无 `agent.write` 时隐藏新建/编辑。
2. [ ] 表单页：`GET /adapters/input` 选适配器 → `@rjsf/core` + `validator-ajv8` 渲染 `configSchema`；提交 `POST /agents`；`ALIAS_TAKEN` 回填到 alias 字段；`DEVICE_OFFLINE` 显示“设备离线”；后端返回 `INTERNAL` 且 `details.reason=agent_provisioning_unavailable`（下发未实现，见 TASK-026 阻塞）时显示“暂不支持从控制台登记，请在节点执行 `workfleet-node agent add`”。
3. [ ] `features/chat/commands`：输入 `/` 或 `／` 弹出候选（来自 im-commands.json，按权限过滤），键盘上下选择；`@` 弹出智能体别名候选；system 消息以区别样式渲染。
4. [ ] 历史页：q / displayId / nativeSessionId 三选一表单 + includeAgentTranscript 开关；结果按会话分组、generation 分段显示；智能体转录为 null 时显示 offline 态与原因（`X-WF-Transcript` 响应头）。
5. [ ] 三个 screen 的 6 态与 `data-ux-state`；文案进 i18n 命名空间。
6. [ ] 测试：rjsf 按 configSchema 渲染并提交；`ALIAS_TAKEN` 字段错误；补全按权限过滤（viewer 看不到 `/clear`）；历史页三种查询与 offline 分支。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`pnpm -F @workfleet/web test src/features/agents src/features/chat/commands src/features/history` 全绿。
- [ ] AC-2：表单组件测试：给定 claude-code 的 configSchema 渲染出 workdir、writeMode 字段；提交返回 409 `ALIAS_TAKEN` 时 alias 字段显示错误。
- [ ] AC-3：指令补全：viewer 权限下候选不含 `/clear`、`/stop`；admin 下包含全部 12 条。
- [ ] AC-4：历史页：`displayId` 查询结果按 generation 分组显示；`agentTranscript:null` 时转录区 `data-ux-state=offline`。
- [ ] AC-5：`agent_list`、`agent_form`、`conversation_history` 三屏 6 态均有测试。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/web test src/features/agents src/features/chat/commands src/features/history
pnpm -F @workfleet/web typecheck && pnpm -F @workfleet/web build
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-027/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/web/src/pages/agents/**`
- `apps/web/src/features/agents/**`
- `apps/web/src/pages/history/**`
- `apps/web/src/features/history/**`
- `apps/web/src/features/chat/commands/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-027/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-027/` 除外）
- `apps/web/src/features/chat/**` 中除 `commands/**` 外的路径（TASK-012；需新扩展点时 blocked 提单）
- `apps/web/src/{app,components,data-access,lib,styles,i18n}/**`（TASK-009）
- `apps/web/src/features/approvals/**`（TASK-029）
- `apps/relay/**`、`apps/node/**`

## 11. 依赖与阻塞
- Depends on：TASK-012, TASK-026
- Blocks：TASK-029, TASK-046
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - TASK-012 的 Composer 未提供补全挂载点 → blocked 提单 TASK-012
  - `POST /api/v1/agents` 下发能力被 TASK-026 标为 blocked → 表单提交走降级提示，不视为本卡失败
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：Schema 驱动表单与页面组合属主力档前端工作，sonnect 足够。

## 13. 升级条件
- rjsf 无法表达某 configSchema（如自定义控件）需扩展契约 → 升 opus 并 blocked
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
大　是否小于 2 小时：否

## 15. 风险与假设
- 假设：`GET /agents` 过滤参数名 `projectId`/`deviceId`（契约未声明）。
- 风险：13 个 ACP 适配器的 configSchema 目前大多只有 workdir/writeMode，表单价值有限；S4 实测后会扩展。
- 本卡不涉及 U-02…U-08。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-027/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
