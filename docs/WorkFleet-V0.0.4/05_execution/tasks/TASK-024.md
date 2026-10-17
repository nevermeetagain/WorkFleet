# TASK-024：指令解析器（im-commands.json）与 Web 渠道指令执行

```yaml
id: TASK-024
slice: S1
status: todo
owner: Agent-Relay
tier: sonnect
size: 中
title: "指令解析器（im-commands.json）与 Web 渠道指令执行"
dependsOn: ["010"]
blocks: ["028", "044"]
reqs: "REQ-F-018"
allowedPaths: ["apps/relay/src/modules/commands/**", "apps/relay/tests/**/commands/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-024/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S1
- 来源需求：REQ-F-018（tasks.v1.json 原值 `REQ-F-018`）
- 来源方案：REQ-F-018（指令以 `commands/im-commands.json` 为准，所有渠道与 Web 行为一致）、architecture §6.1 第 3 步（解析指令后再选路）、DESIGN-005 交互（文档未落地）

## 2. 目标
中转具备与渠道无关的指令解析器与执行器注册表；Web 渠道发送以 `/` 或 `／` 开头的文本时按 im-commands.json 解析、做权限校验并执行，结果以 system 消息回到会话。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-018、REQ-F-019
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §6.1
  - docs/WorkFleet-V0.0.4/00_governance/glossary.md（焦点、代、急停）
- 契约：
  - `packages/contracts/commands/im-commands.json`：prefixes `/`、`／`；`/help`(conversation.read)、`/list`(agent.read)、`/use <alias>`(agent.prompt)、`/@alias <text>`（写法 `@z1 文本`，agent.prompt）、`/clear [alias]`(conversation.write)、`/stop [alias]`(agent.stop)、`/stop all`(emergency.stop_all)、`/status [alias]`(agent.read)、`/history [displayId|resumeId] [n]`(history.search)、`/bind`(recipient.authorize)、`Y{n} / N{n}`(approval.decide_low)、`/boss <text>`(agent.prompt)
  - `packages/contracts/identity/permissions.json`（经 `tenancy.assertPermission` 校验每条指令的 permission）
  - `packages/contracts/protocol/frames/agent.clear.schema.json`、`agent.cancel.schema.json`（/clear、/stop 经 conversations 模块发出）
  - `packages/contracts/schemas/entities/message.schema.json`（结果写为 direction=system、author.kind=system）；错误码 `FORBIDDEN`、`NOT_FOUND`
- 前置任务：TASK-010
- 前置状态：TASK-010 已合并（conversations 公开 `registerInboundInterceptor`、`findByDisplayId`、`findByNativeSessionId`、`listMessages`、`sendPrompt`；`/clear`、`/cancel` 端点）

## 4. 输出
- `apps/relay/src/modules/commands/domain/{parser.ts,command.ts}`：纯函数 `parse(text) → Command | null`（支持全角斜杠、`@alias 文本`、`Y3`/`n3` 大小写、`/stop all` 与 `/stop z1` 区分）
- `apps/relay/src/modules/commands/application/{registry.ts,execute.ts,web/**}`：执行器注册表 `registerCommand(name, handler)`；Web 渠道内置执行器 help/list/use/at-alias/clear/stop/status/history
- `apps/relay/src/modules/commands/index.ts`（公开 `parse()`、`registerCommand()`、`executeCommand(ctx)`；`register(app)` 中向 conversations 注册入站拦截器）
- 测试：`apps/relay/tests/unit/modules/commands/**`（解析表驱动用例，从 im-commands.json 生成）、`apps/relay/tests/integration/modules/commands/**`

## 5. Execution Steps
1. [ ] 实现 `parser.ts`：读取 im-commands.json 的 prefixes 与 syntax；输出 `{name, args, raw}`；非指令文本返回 null（普通消息照常路由）；未知指令返回 `{name:'unknown'}`。
2. [ ] 实现 `registry.ts`/`execute.ts`：执行前按 im-commands.json 的 permission 调 `tenancy.assertPermission`，无权→system 消息“无权限执行该指令”（审计留给 TASK-143）；未注册执行器的指令（`/stop all`、`/bind`、`Y{n}/N{n}`、`/boss`）→ system 消息“该指令暂未启用”，供后续任务注册覆盖。
3. [ ] Web 执行器：`/help` 列出当前角色可用指令；`/list` 列出组织内智能体（alias、设备、项目、状态）；`/use <alias>` 在 Web 渠道打开/创建与该智能体的会话并返回其 conversationId 与 displayId；`@alias 文本` 发送到该智能体会话。
4. [ ] Web 执行器续：`/clear [alias]`、`/stop [alias]` 调 conversations 的 clear/cancel；`/status [alias]` 返回状态与排队数；`/history [displayId|resumeId] [n]`（默认 10）经 `findByDisplayId`/`findByNativeSessionId` + `listMessages` 返回最近 n 条摘要。
5. [ ] 在 `index.ts` 的 `register` 中调用 `conversations.registerInboundInterceptor`，使 `POST /api/v1/conversations/{conversationId}/messages` 的指令文本被拦截执行，原文仍作为 inbound 消息入账。
6. [ ] 表驱动测试：im-commands.json 中每条 syntax 至少 1 正例 1 反例；全角 `／list` 等价 `/list`；viewer 执行 `/clear` 得到无权限提示。
7. [ ] 集成测试：Web 发 `/clear` → 会话 generation+1；发 `/history WF-1 3` → system 消息含 3 条；发 `/foo` → 未知指令提示。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：解析器表驱动测试覆盖 im-commands.json 全部 12 条 syntax，正反例全部通过；`／list` 与 `/list` 解析结果相同。
- [ ] AC-2：Web 渠道发送 `/clear` → 会话 generation 由 1 变 2，返回 system 消息；发送 `/history <displayId> 3` → system 消息列出 3 条。
- [ ] AC-3：viewer 角色发送 `/clear`（需 conversation.write）→ system 消息提示无权限，generation 不变。
- [ ] AC-4：`/stop all`、`/bind`、`Y1`、`/boss x` 在未注册执行器时返回“暂未启用”提示且不抛错；注册测试执行器后改由其处理。
- [ ] AC-5：非指令文本（如 `hello /x`）不被拦截，正常转发 `agent.prompt`。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/relay test tests/unit/modules/commands tests/integration/modules/commands
pnpm -F @workfleet/relay typecheck
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-024/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/relay/src/modules/commands/**`
- `apps/relay/tests/**/commands/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-024/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-024/` 除外）
- `apps/relay/src/modules/commands/application/approval-codes/**`（TASK-047）
- `apps/relay/src/modules/{conversations,approvals,recipients,routing}/**`
- `apps/web/**`

## 11. 依赖与阻塞
- Depends on：TASK-010
- Blocks：TASK-028, TASK-044
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - TASK-010 未提供 `registerInboundInterceptor` 等扩展点 → blocked 提单 TASK-010 补（本卡不得改 conversations）
  - `/use` 在 Web 渠道的语义（契约描述为“把当前对话的默认目标切到该智能体”，Web 无接收人焦点表）→ 本卡按“切换/打开该智能体会话”实现，IM 侧焦点语义归 TASK-044
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：解析器是纯函数 + 表驱动测试，执行器为薄编排，sonnect 足够。

## 13. 升级条件
- 指令在不同渠道语义无法统一（REQ-F-018 一致性）需要改 im-commands.json → 升 opus 并 blocked
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：未启用指令的统一提示文案为本卡假设，最终文案进 i18n 资源。
- 风险：`/history` 的 resumeId 即 nativeSessionId，若多个会话共享同一原生 id（智能体复用）将返回多条 → 取最近一条并提示。
- 本卡不涉及 U-02…U-08。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-024/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
