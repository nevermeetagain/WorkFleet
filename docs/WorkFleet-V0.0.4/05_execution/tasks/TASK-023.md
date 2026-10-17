# TASK-023：sessions：转录 JSONL+索引、/clear（generation）、loadSession 恢复、history.query/result

```yaml
id: TASK-023
slice: S1
status: todo
owner: Agent-Node
tier: sonnect
size: 中
title: "sessions：转录 JSONL+索引、/clear（generation）、loadSession 恢复、history.query/result"
dependsOn: ["021"]
blocks: ["030", "063"]
reqs: "REQ-F-019"
allowedPaths: ["apps/node/src/modules/sessions/**", "apps/node/tests/**/sessions/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-023/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S1
- 来源需求：REQ-F-019（tasks.v1.json 原值 `REQ-F-019`）
- 来源方案：architecture §4.2（sessions：生命周期、/clear generation+1、resume、转录 JSONL + 索引）/§7（完整转录只在节点）、ADR-003；V0.0.2 ACP 分析 C4/C5（ACP 无 /clear 原语；session/load 回放、session/resume 不回放）

## 2. 目标
节点为每个会话代（conversationId + generation）持久化完整转录（JSONL + `transcript_index`/`transcript_fts`），`agent.clear` 使 generation+1 并新开 ACP 会话，节点重启后按能力 `session/load`/`session/resume` 恢复，`history.query` 返回 `history.result`。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.2、§7
  - docs/WorkFleet-V0.0.2/30-协议与端点/01-ACP协议深度分析.md（ACP v1：initialize、session/new、session/prompt、session/update、session/request_permission、session/cancel、session/load、session/resume、session/close；v2 为 draft）
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-019
- 契约：
  - `packages/contracts/protocol/frames/agent.clear.schema.json`（agentId、conversationId、newGeneration≥2）、`history.query.schema.json`（requestId、conversationId、generation|null、limit 1–200）、`history.result.schema.json`（requestId、entries[]——条目结构未定义）、`agent.output.schema.json`（nativeSessionId）
  - `packages/contracts/adapters/input-adapter-spec.schema.json`：`supportsLoadSession`（内置表除 coze 外均为 false，待实测）
  - 表（node）：`sessions`（PK conversation_id+generation、native_session_id、transcript_path、state）、`transcript_index`（line_no、role、plain_text）、`transcript_fts`（content=transcript_index，无同步触发器，需应用层写入）
- 前置任务：TASK-021
- 前置状态：TASK-021 已合并（Host 发出进程内事件 `agent.session_update`，agents 模块 index 公开 `closeSession()`/`openSession()`）

## 4. 输出
- `apps/node/src/modules/sessions/{domain,application,interfaces,infrastructure}/**`、`index.ts`
- 转录文件：`<WF_NODE_DATA_DIR>/transcripts/<conversationId>/<generation>.jsonl`（每行 `{lineNo, role: user|agent|tool|system, text, createdAt, raw?}`）
- 测试：`apps/node/tests/unit/modules/sessions/**`、`apps/node/tests/integration/modules/sessions/**`

## 5. Execution Steps
1. [ ] 订阅 `agent.session_update` 与 prompt 入队事件：首次出现某 conversationId+generation 时写 `sessions`；每条用户输入/智能体输出/工具调用摘要追加一行 JSONL，同事务写 `transcript_index` 并 `INSERT INTO transcript_fts(rowid, plain_text)`。
2. [ ] 记录 ACP `sessionId` 为 `native_session_id`，并在下一次 `agent.output` 中携带 `nativeSessionId` 供中转会话关联（REQ-F-019）。
3. [ ] `agent.clear`：将旧代 `sessions.state=cleared`，调用 agents 模块关闭旧 ACP 会话（支持 `session/close` 则调用，否则结束子进程），新代在下一个 prompt 时 `session/new`；旧代转录保持可查。
4. [ ] 恢复：节点启动时对 active 会话按能力选择 `session/load`（`supportsLoadSession` 且智能体 `loadSession` 能力为真）→ `session/resume`（`sessionCapabilities.resume`）→ 否则新会话并写 system 行“上下文未恢复”。
5. [ ] `history.query`：按 conversationId（+可选 generation）读 `transcript_index` 最近 `limit` 条，回 `history.result{requestId, entries}`，条目结构 `{generation,lineNo,role,text,createdAt}`（契约未定义，本卡假设并登记）；单帧超 1 MiB 时截断并在最后一条标注 `truncated`。
6. [ ] 提供本地检索函数 `searchTranscript(q)`（trigram FTS，供后续本机控制台使用）。
7. [ ] 测试：转录写入与 FTS 命中（中文 ≥3 字）；clear 后 generation=2 且旧代可查；重启恢复三条分支；`history.result` 通过 schema 且尊重 limit；超大转录截断。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：一轮对话后 `<dataDir>/transcripts/<cnv>/1.jsonl` 行数 ≥2，`transcript_index` 行数一致，`transcript_fts MATCH '<中文三字>'` 命中。
- [ ] AC-2：收到 `agent.clear{newGeneration:2}` 后下一轮写入 `2.jsonl`，旧会话 state=cleared，`history.query{generation:1}` 仍返回旧记录（REQ-F-019）。
- [ ] AC-3：`history.query{limit:5}` 回的 `history.result` 通过 `history.result.schema.json`，entries ≤5 且 requestId 对应。
- [ ] AC-4：节点重启：spec 声明不支持 loadSession 时走“新会话 + system 行”分支；支持时调用 `session/load`（FakeAgent 夹具验证）。
- [ ] AC-5：`agent.output.nativeSessionId` 与 `sessions.native_session_id` 一致。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/node test tests/unit/modules/sessions tests/integration/modules/sessions
pnpm -F @workfleet/node typecheck
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-023/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/node/src/modules/sessions/**`
- `apps/node/tests/**/sessions/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-023/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-023/` 除外）
- `apps/node/src/modules/agents/**`（TASK-021/022；需要新 Host API 时 blocked 提单）
- `apps/node/src/modules/{relay-link,workspace-guard,system}/**`
- `apps/relay/**`

## 11. 依赖与阻塞
- Depends on：TASK-021
- Blocks：TASK-030, TASK-063
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - `history.result.entries` 条目结构契约未定义 → 本卡按上述假设实现；若 TASK-025 期望不同结构，需先补契约（blocked）
  - TASK-021 未提供关闭/重开会话的公开 API → blocked 提单 TASK-021 补
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：持久化 + 帧处理，规则已由 architecture 与 ACP 分析确定，sonnect 足够。

## 13. 升级条件
- 恢复逻辑与真实智能体行为不符（真机 session/load 回放导致重复转录）→ 升 opus 复核恢复策略
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-05）：各智能体 `loadSession`/`resume` 能力以运行时 initialize 返回为准，表中值待实测。
- 风险：trigram FTS 对 <3 字查询无效 → 本地检索对短词退回 LIKE。
- 风险：转录含敏感代码，仅存节点（DEC-037），不随 `history.result` 以外的途径上送。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-023/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
