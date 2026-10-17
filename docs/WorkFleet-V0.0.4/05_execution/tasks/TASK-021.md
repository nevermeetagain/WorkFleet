# TASK-021：通用 ACP Host：spawn/initialize/session.new/prompt/cancel、进程树监管、权限请求→approval.request

```yaml
id: TASK-021
slice: S1
status: todo
owner: Agent-Node
tier: opus
size: 大
title: "通用 ACP Host：spawn/initialize/session.new/prompt/cancel、进程树监管、权限请求→approval.request"
dependsOn: ["011"]
blocks: ["022", "023", "064", "085", "086"]
reqs: "REQ-F-007"
allowedPaths: ["apps/node/src/modules/agents/** (除 adapters/specs、application/echo)", "apps/node/tests/**/agents/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-021/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S1
- 来源需求：REQ-F-007（tasks.v1.json 原值 `REQ-F-007`）
- 来源方案：ADR-007（通用 ACP 适配器 + InputAdapterSpec 表）、architecture §4.2（agents：进程监管 Windows Job Object / POSIX 进程组、权限请求转审批）/§6.1 第 6 步（DEC-017：只回传完成/失败/审批/阻塞或可编辑状态卡）、REQ-NF-002（≥8 并发会话、空闲 15 分钟回收）

## 2. 目标
节点内的通用 ACP Host 可按 InputAdapterSpec 为每个会话拉起一个智能体子进程，完成 initialize → session/new → session/prompt → session/cancel，监管整棵进程树，并把 `session/request_permission` 转为 `approval.request` 帧、按 `approval.decision` 回复智能体。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-007-输入端.md
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.2、§6.1
  - docs/WorkFleet-V0.0.2/30-协议与端点/01-ACP协议深度分析.md（ACP v1：initialize、session/new、session/prompt、session/update、session/request_permission、session/cancel、session/load、session/resume、session/close；v2 为 draft）
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-007、REQ-F-020、REQ-NF-002
- 契约：
  - `packages/contracts/adapters/input-adapter-spec.schema.json`（launch.command/args/windowsCommand/env/cwdMode、auth、dialect、supportsLoadSession、supportsWriteTools）、`adapters/input-adapters.v1.json`（只读，作为内置后备表）
  - `packages/contracts/protocol/frames/agent.prompt.schema.json`、`agent.cancel.schema.json`（入）；`agent.output.schema.json`（kind final|status|error，priority）、`agent.status.schema.json`（idle|running|waiting_approval|stopped|error|unavailable、queueDepth）、`approval.request.schema.json`（出）；`approval.decision.schema.json`（入：approvalId、optionId、decidedBy）；`agents.sync.schema.json`（出）
  - `packages/contracts/schemas/entities/approval.schema.json`（kind=tool_permission、risk low|medium|high、options[optionId,label,kind allow_once|allow_always|reject|custom]、expiresAt）、`schemas/entities/agent.schema.json`
  - `packages/contracts/errors/error-codes.json`：`AGENT_UNAVAILABLE`（可执行文件缺失或启动失败）
  - 表（node）：`agents`、`prompt_queue`（每会话串行）、`pending_permissions`（approval_id、acp_request_id、options）
- 前置任务：TASK-011
- 前置状态：TASK-011 已合并（agents 模块入口、回声执行器、relay-link 帧收发、CLI 扩展点）

## 4. 输出
- `apps/node/src/modules/agents/domain/**`（AgentInstance、Session 运行态、风险分级策略、PermissionMapping）
- `apps/node/src/modules/agents/application/{run-prompt,cancel,handle-permission,supervise,sync-agents,register-agent}/**`
- `apps/node/src/modules/agents/infrastructure/{acp-client,process,persistence}/**`：`acp-client`（JSON-RPC over stdio；ACP TS SDK 若经 U-05 实测可用则封装之）、`process/`（Windows Job Object / POSIX `detached` 进程组 + `kill(-pgid)`）
- `apps/node/src/modules/agents/interfaces/{relay,cli,http}/**`：订阅 `agent.prompt`/`agent.cancel`/`approval.decision`；CLI `workfleet-node agent add --alias --adapter --workdir [--write] [--project]`；`GET /local/v1/adapters/detect` 路由（调用 SpecSource 端口）
- `apps/node/src/modules/agents/index.ts`（在保留回声注册的前提下增加 Host 注册；`WF_NODE_ECHO_MODE=1` 时仍走回声）
- 测试：`apps/node/tests/unit/modules/agents/**`、`apps/node/tests/integration/modules/agents/**`（以 `fake-acp-agent --fixture` 作为被拉起的智能体）

## 5. Execution Steps
1. [ ] 定义 `SpecSource` 端口（`list()`、`get(adapterId)`、`detect()`）；组合根优先加载 `infrastructure/specs/index.ts`（TASK-022 提供），不存在时退回内置只读加载器（直接读 `@workfleet/contracts` 的 input-adapters.v1.json）；本卡不写 `infrastructure/specs/**`。
2. [ ] 进程层：按 spec 拉起子进程（Windows 优先 `windowsCommand`；`cwdMode=workdir` 用 agent.workdir），stdio 管道；Windows 用 Job Object（KILL_ON_JOB_CLOSE），POSIX 用独立进程组；可执行文件缺失或握手超时（30 s）→ `agent.status{status:unavailable}` 并对当前 prompt 回 `agent.output{kind:error}`（`AGENT_UNAVAILABLE`）。
3. [ ] ACP 客户端：`initialize{protocolVersion:1, clientCapabilities:{fs:false,terminal:false}}` → `session/new{cwd, mcpServers:[]}`；每个 conversationId+generation 一个会话一个子进程；`prompt_queue` 保证同会话串行，跨会话并发上限默认 8（REQ-NF-002）。
4. [ ] `agent.prompt` 处理：入队→`session/prompt{sessionId,prompt:[{type:text,text}]}`；`session/update` 只在节点聚合（`agent_message_chunk` 拼接、`tool_call` 计数），按 DEC-017 仅在 turn 结束回 `agent.output{kind:final}`，长任务每 ≥10 s 最多一次 `kind:status`（body 为 `status_card`）；同时发进程内事件 `agent.session_update` 供 sessions 模块（TASK-023）落转录。
5. [ ] `agent.cancel` → `session/cancel`（通知）；超时 10 s 未结束则杀进程树；回 `agent.status{status:stopped}`。
6. [ ] 权限：`session/request_permission` → 写 `pending_permissions` → 发 `approval.request{approval}`（id `apr_`+ULID、kind `tool_permission`、summary 取 toolCall 标题、risk 按工具类别：read/search/think/fetch→low，edit/move→medium，delete/execute→high（本卡假设）、options 由 ACP options 映射、expiresAt=now+10 min 可配、shortCode 暂填 1 由中转重分配）→ `agent.status{waiting_approval}`；收到 `approval.decision` 以对应 optionId 回复 ACP 并清理记录。
7. [ ] 监管：子进程异常退出→回 `agent.output{kind:error}`、状态 error、下次 prompt 重新拉起；空闲 15 分钟回收子进程（REQ-NF-002）；节点退出时清理全部进程树。
8. [ ] 智能体登记：CLI `agent add` 写本地 `agents`，经 `agents.sync{agents:[…]}` 全量上报（hello 时也上报）；未指定 `--project` 时 projectId 填占位 `prj_00000000000000000000000000`，由中转 TASK-026 映射到默认项目（契约缺“中转→节点登记”帧的权宜方案）。
9. [ ] 测试：FakeAgent `basic.jsonl` 多轮；`permission.jsonl` 产生 schema 合法的 `approval.request` 并在 decision 后继续；`cancel.jsonl`；8 个会话并发；杀子进程后进程树无残留（POSIX 检查 pgid、Windows 检查 Job 内进程数）。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：集成测试：FakeRelay 发 `agent.prompt` → 节点拉起 `fake-acp-agent --fixture basic.jsonl`，回 `agent.output{kind:final}`，payload 通过 schema；同会话第二轮复用同一子进程（pid 不变）。
- [ ] AC-2：`permission.jsonl`：节点发出的 `approval.request` 通过 `approval.request.schema.json`，`agent.status=waiting_approval`；FakeRelay 回 `approval.decision{optionId:allow_once}` 后 FakeAgent 收到对应 outcome，turn 正常结束。
- [ ] AC-3：`agent.cancel` 后 ≤10 s 收到 `agent.status{status:stopped}`；cancel/异常退出后 `ps`（或 Windows 任务列表）中无该会话的残留子进程。
- [ ] AC-4：spec 中命令不存在 → 收到 `agent.status{status:unavailable}` 与 `agent.output{kind:error}`，错误体码为 `AGENT_UNAVAILABLE`。
- [ ] AC-5：8 个会话并发 prompt 全部完成；空闲回收在假时钟 15 分钟后触发（REQ-NF-002）。
- [ ] AC-6：`workfleet-node agent add` 后中转侧（FakeRelay）收到通过 schema 的 `agents.sync` 帧。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/node test tests/unit/modules/agents tests/integration/modules/agents
pnpm -F @workfleet/node typecheck
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-021/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/node/src/modules/agents/** (除 adapters/specs、application/echo)`
- `apps/node/tests/**/agents/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-021/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-021/` 除外）
- `apps/node/src/modules/agents/infrastructure/specs/**`（TASK-022；allowedPaths 写的是“除 adapters/specs”，与 TASK-022 的 `infrastructure/specs` 路径不一致，本卡按 TASK-022 的实际路径回避）
- `apps/node/src/modules/agents/application/echo/**`（TASK-011）
- `apps/node/src/modules/agents/infrastructure/{coze,webhook,dialects}/**`（TASK-084/085/086）
- `apps/node/src/modules/{sessions,relay-link,workspace-guard,system}/**`
- `packages/testkit/**`、`apps/relay/**`

## 11. 依赖与阻塞
- Depends on：TASK-011
- Blocks：TASK-022, TASK-023, TASK-064, TASK-085, TASK-086
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - ACP TypeScript SDK 包名/版本无法确认（U-05）→ 不阻塞：自写 JSON-RPC 客户端；若主 Agent 要求必须用 SDK 且需新增依赖 → blocked 提单 Agent-Guard 改 `apps/node/package.json`
  - 契约无“中转→节点”智能体登记/更新帧（`POST /api/v1/agents` 无法下发）→ 本卡用节点侧 CLI 登记 + `agents.sync` 权宜；若裁定必须由控制台登记则 blocked 等契约新增帧
  - `approval.request` 要求节点给出组织内唯一的 `shortCode`，节点无法保证 → 依赖 TASK-028 在中转重分配；若中转不重分配则 blocked
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
opus　理由：进程树监管、ACP 状态机与审批往返是执行面核心且跨平台，错误会导致僵尸进程或审批丢失，按 opus 执行。

## 13. 升级条件
- 本卡已为 opus：需引入 ACP v2 或修改帧语义 → 升 fable 并 blocked
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
大　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-05）：ACP TS SDK（V0.0.2 记载为 `@agentclientprotocol/sdk`，证据：claude-agent-acp 源码 import）版本与 API 待实测；本卡以自写 JSON-RPC 保底。
- 假设：风险分级（工具类别→low/medium/high）与审批默认 10 分钟过期为本卡设计假设，DESIGN-020/005 文档缺失，待评审。
- 风险：Windows Job Object 需原生绑定（N-API 或 PowerShell 回退）——证据不足/待实测，三平台矩阵由 TASK-014 运行。
- 风险：智能体自身登录态（agent_managed auth）不在 WorkFleet 管理范围，未登录表现为启动失败（product-requirements §8）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-021/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
