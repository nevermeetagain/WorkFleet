# TASK-011：节点回声执行面：接收 agent.prompt，交给 FakeAgent，回 agent.output

```yaml
id: TASK-011
slice: S0
status: todo
owner: Agent-Node
tier: sonnect
size: 小
title: "节点回声执行面：接收 agent.prompt，交给 FakeAgent，回 agent.output"
dependsOn: ["007", "008"]
blocks: ["013", "021"]
reqs: "REQ-F-015"
allowedPaths: ["apps/node/src/modules/agents/application/echo/**", "apps/node/src/modules/agents/index.ts"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-011/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S0
- 来源需求：REQ-F-015（tasks.v1.json 原值 `REQ-F-015`）
- 来源方案：architecture §6.1（第 6 步：节点在会话上执行 prompt 并回传）、REQ-NF-009（FakeAgent）、ADR-007（ACP Host 由 TASK-021 实现，本卡仅回声）

## 2. 目标
节点在回声模式下接收中转的 `agent.prompt`，交给 FakeAgent（ACP 回声），把结果以 `agent.output{kind:final}` 回传，打通 S0 执行面。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.2（agents）、§6.1
  - docs/WorkFleet-V0.0.4/04_planning/slices.md S0 演示脚本
  - packages/testkit/fixtures/acp/README.md（TASK-008 产出的夹具格式）
- 契约：
  - `packages/contracts/protocol/frames/agent.prompt.schema.json`（agentId、conversationId、generation、messageId、body）
  - `packages/contracts/protocol/frames/agent.output.schema.json`（conversationId、generation、messageId、replyToId、kind=final、priority=p2、body、nativeSessionId）、`agent.status.schema.json`（running→idle）
  - `packages/contracts/schemas/entities/message-body.schema.json`（`blocks[{type:paragraph,text}]`）、`schemas/common/ids.schema.json`（messageId `msg_`+ULID）
- 前置任务：TASK-007、TASK-008
- 前置状态：TASK-007（relay-link `onRelayFrame`/`sendToRelay`、模块自动加载）与 TASK-008（`fake-acp-agent --echo`）已合并

## 4. 输出
- `apps/node/src/modules/agents/application/echo/{echo-executor.ts,register.ts}`：订阅 `agent.prompt`，`WF_NODE_ECHO_MODE=1` 时启用
- `apps/node/src/modules/agents/index.ts`（模块入口 `register(ctx)`；仅挂回声执行器，保留给 TASK-021 扩展）
- 测试：`apps/node/tests/unit/modules/agents/echo/**`

## 5. Execution Steps
1. [ ] 在 `agents/index.ts` 导出 `register(ctx)`：读取配置 `WF_NODE_ECHO_MODE`，开启时注册回声执行器，否则不注册（为 TASK-021 留空位）。
2. [ ] `echo-executor.ts`：收到 `agent.prompt` 后，按会话串行（同一 conversationId 排队，简单内存队列即可，prompt_queue 表由 TASK-021 接管），先发 `agent.status{status:running}`。
3. [ ] 以子进程启动 `fake-acp-agent --echo`（来自 `@workfleet/testkit`，devDependency），按 ACP v1 发 initialize→session/new→session/prompt（文本取 body 的 paragraph 块拼接）。
4. [ ] 收集 `agent_message_chunk` 拼成回复，组装 `agent.output{conversationId,generation,messageId:新 msg_ULID,replyToId:prompt.messageId,kind:'final',priority:'p2',body:{blocks:[{type:'paragraph',text}]}}` 经 `sendToRelay` 发送，再发 `agent.status{status:idle,queueDepth}`。
5. [ ] FakeAgent 进程异常退出→回 `agent.output{kind:'error'}`（body 为 callout error）并 `agent.status{status:error}`。
6. [ ] 写测试（使用 TASK-008 FakeRelay）：发 `agent.prompt{text:"hello"}` → 收到通过 schema 校验的 `agent.output`，文本为 `echo: hello`、`replyToId` 正确；同会话连发两条按序回复。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：FakeRelay 发 `agent.prompt`（body 文本 `hello`）→ 5 s 内收到 `agent.output`，payload 通过 `agent.output.schema.json`，文本 `echo: hello`，`replyToId` = prompt 的 messageId。
- [ ] AC-2：同一会话连续 2 条 prompt 的回复按发送顺序到达；收到 `agent.status` 序列 running→idle。
- [ ] AC-3：FakeAgent 异常退出时回传 `kind:error` 的 `agent.output` 与 `agent.status{status:error}`。
- [ ] AC-4：`WF_NODE_ECHO_MODE` 未设置时不注册回声执行器（单测断言订阅者为空）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/node test tests/unit/modules/agents/echo
pnpm -F @workfleet/node typecheck
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-011/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/node/src/modules/agents/application/echo/**`
- `apps/node/src/modules/agents/index.ts`
- 明确写出的测试目录（本模块专属；allowedPaths 未含测试路径，按任务指令 §3 在此显式声明，执行前须经主 Agent 确认）：
  - `apps/node/tests/unit/modules/agents/echo/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-011/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-011/` 除外）
- `apps/node/src/modules/agents/**` 中除 `application/echo/**` 与 `index.ts` 外的路径（TASK-021/022 及 S4 任务）
- `apps/node/src/modules/{relay-link,sessions,system}/**`
- `packages/testkit/**`（只读使用）
- `apps/relay/**`

## 11. 依赖与阻塞
- Depends on：TASK-007, TASK-008
- Blocks：TASK-013, TASK-021
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 生产代码依赖 `@workfleet/testkit` 需 `apps/node/package.json` 声明（TASK-001 所有）→ 若未预声明为 devDependency 则 blocked 提单
  - 节点侧没有该 agentId 的本地记录（S0 智能体由中转开发种子产生，节点未收到登记帧）→ 回声模式对任意 agentId 应答；这是 S0 权宜做法，TASK-021 需改为按本地 agents 表校验
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：单一帧处理 + 子进程调用，范围小、可逆，sonnect 足够。

## 13. 升级条件
- 回声链路在 TASK-013 E2E 中连续 2 次超时/丢回复 → 升 opus 排查 relay-link 与执行面交互
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
小　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-05）：本卡不使用 ACP SDK，直接 JSON-RPC；TASK-021 引入 SDK 后可替换。
- 风险：回声模式对任意 agentId 应答，若误在生产开启会绕过智能体登记 → 生产配置拒绝 `WF_NODE_ECHO_MODE`。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-011/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
