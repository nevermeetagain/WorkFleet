# TASK-025：历史检索 API：FTS trigram、displayId、nativeSessionId、节点转录拉取

```yaml
id: TASK-025
slice: S1
status: todo
owner: Agent-Relay
tier: sonnect
size: 中
title: "历史检索 API：FTS trigram、displayId、nativeSessionId、节点转录拉取"
dependsOn: ["010"]
blocks: []
reqs: "REQ-F-019"
allowedPaths: ["apps/relay/src/modules/conversations/application/history/**", "apps/relay/src/modules/conversations/interfaces/http/history*"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-025/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S1
- 来源需求：REQ-F-019（tasks.v1.json 原值 `REQ-F-019`）
- 来源方案：REQ-F-019（按 display_id 或原生 resume_id 查到两端记录）、architecture §4.1（conversations：FTS 检索）/§7（完整转录只在节点，中转只存引用）、ADR-009 风险（长查询 FTS 放 worker_threads）

## 2. 目标
`GET /api/v1/history/search` 支持中文 trigram 全文检索、按 displayId、按 nativeSessionId 三种查询，并可在节点在线时经 `history.query`/`history.result` 拉取智能体侧转录，一次返回两端记录。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-019、REQ-F-002
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.1、§7
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-009-后端运行栈.md
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/history/search`（`history.search`；响应 `{conversations: Conversation[], messages: Message[], agentTranscript: array|null}`；摘要写明参数 q / displayId / nativeSessionId / includeAgentTranscript，但 operation 未声明 parameters）
  - `packages/contracts/protocol/frames/history.query.schema.json`（requestId、conversationId、generation|null、limit≤200）、`history.result.schema.json`（requestId、entries[]）
  - `packages/contracts/schemas/entities/{conversation,message}.schema.json`；`identity/permissions.json`（跨组织 404、projectScope 过滤）
  - 表：`messages_fts`（fts5 trigram，content=messages）、`messages`、`conversations`（`ux_conversations_display`、`ix_conversations_native`）
- 前置任务：TASK-010
- 前置状态：TASK-010 已合并（conversations 模块、路由聚合器加载 `interfaces/http/history.routes.ts` 占位、`application/history/index.ts` 占位）；节点侧 `history.result` 由 TASK-023 提供（联调用 FakeRelay 的对偶模拟即可）

## 4. 输出
- `apps/relay/src/modules/conversations/application/history/{search-history.ts,fetch-agent-transcript.ts,fts-worker.ts,index.ts}`
- `apps/relay/src/modules/conversations/interfaces/http/history.routes.ts`（替换 TASK-010 的占位插件）、`interfaces/http/history.schema.ts`（查询参数 ajv schema：`q`、`displayId`、`nativeSessionId`、`includeAgentTranscript`、`limit`）
- 测试：`apps/relay/tests/unit/modules/conversations/history/**`、`apps/relay/tests/integration/modules/conversations/history/**`

## 5. Execution Steps
1. [ ] 定义查询参数（契约缺失，按 summary 推定并登记）：`q`、`displayId`、`nativeSessionId` 三选一必填（全缺→400 `VALIDATION_FAILED`）；`includeAgentTranscript` 默认 false；`limit` 1–200 默认 50。
2. [ ] `q` 检索：长度 ≥3 走 `messages_fts MATCH`（trigram），<3 退回 `plain_text LIKE`；JOIN conversations 限定 `tenant_id = principal.tenantId` 且符合 projectScope；查询放 `worker_threads`（`fts-worker.ts`）避免阻塞事件循环。
3. [ ] `displayId`/`nativeSessionId`：精确匹配会话，返回会话及其各代消息（按 generation、created_at 排序）。
4. [ ] `includeAgentTranscript=true` 且命中单一会话：设备在线→`sendToNode('history.query',{requestId,conversationId,generation,limit})`，按 requestId 等待 `history.result`（超时 5 s）填入 `agentTranscript`；离线或超时→`agentTranscript:null`（响应头 `X-WF-Transcript: offline|timeout` 说明原因）。
5. [ ] `onNodeFrame('history.result')` 订阅只处理本进程挂起的 requestId，其余丢弃并记日志。
6. [ ] 测试：中文三字词命中、两字词走 LIKE；跨组织数据不可见；viewer 可查（history.search 三角色皆可）；displayId 命中多代；节点在线/离线/超时三分支。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：集成测试：写入含“部署脚本”的消息后 `GET /history/search?q=部署脚本` 命中；`q=部署` 走 LIKE 分支仍命中；响应通过 openapi 响应 schema。
- [ ] AC-2：`GET /history/search?displayId=<id>` 返回该会话 generation 1 与 2 的消息（/clear 后旧记录仍可查，REQ-F-019）。
- [ ] AC-3：`nativeSessionId` 查询返回对应会话；另一组织的同名 id 不返回（REQ-F-002）。
- [ ] AC-4：节点在线时 `includeAgentTranscript=true` 返回 FakeRelay 对偶模拟的 entries；离线时 `agentTranscript:null` 且响应 200。
- [ ] AC-5：三个查询参数都缺失→400 `VALIDATION_FAILED`。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/relay test tests/unit/modules/conversations/history tests/integration/modules/conversations/history
pnpm -F @workfleet/relay typecheck
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-025/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/relay/src/modules/conversations/application/history/**`
- `apps/relay/src/modules/conversations/interfaces/http/history*`
- 明确写出的测试目录（本模块专属；allowedPaths 未含测试路径，按任务指令 §3 在此显式声明，执行前须经主 Agent 确认）：
  - `apps/relay/tests/unit/modules/conversations/history/**`
  - `apps/relay/tests/integration/modules/conversations/history/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-025/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-025/` 除外）
- `apps/relay/src/modules/conversations/**` 中除 `application/history/**` 与 `interfaces/http/history*` 外的路径（TASK-010）
- `apps/relay/src/modules/{node-gateway,commands}/**`
- `apps/node/**`、`apps/web/**`

## 11. 依赖与阻塞
- Depends on：TASK-010
- Blocks：—
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - `GET /api/v1/history/search` 的 parameters 未在 openapi 声明 → 按 summary 实现并登记；若主 Agent 要求先补契约则 blocked
  - TASK-010 未留占位/未加载 `history.routes.ts` → 本卡无法挂路由（不得改 conversations 其他文件）→ blocked
  - `history.result.entries` 结构未定义，与 TASK-023 的条目结构不一致 → blocked 等契约补齐
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：检索与一次请求-响应帧编排，规则清晰，sonnect 足够。

## 13. 升级条件
- FTS 查询 p95 > 200 ms 或阻塞事件循环导致其他测试超时 → 升 opus 评审存储策略（ADR-003 迁移触发条件）
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：查询参数名按 openapi summary 推定（契约缺 parameters）。
- 假设（NON_BLOCKING，U-04）：跨境拉取转录 5 s 超时足够，实际 RTT 由 TASK-041/210 测量。
- 风险：trigram 索引体积随消息增长，ADR-003 的 20 GB 迁移触发条件需监控。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-025/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
