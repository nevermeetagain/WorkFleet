# TASK-008：testkit：FakeAgent（ACP 录制回放）、FakeChannel、FakeRelay

```yaml
id: TASK-008
slice: S0
status: todo
owner: Agent-QA
tier: sonnect
size: 中
title: "testkit：FakeAgent（ACP 录制回放）、FakeChannel、FakeRelay"
dependsOn: ["002"]
blocks: ["011", "105"]
reqs: "REQ-NF-009"
allowedPaths: ["packages/testkit/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-008/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S0
- 来源需求：REQ-NF-009（tasks.v1.json 原值 `REQ-NF-009`）
- 来源方案：REQ-NF-009（CI 不依赖真实 IM 与智能体）、ADR-007（新增智能体 = 一条 spec + 一个录制夹具）、ADR-005（FakeRelay 说同一 envelope）、architecture §3（packages/testkit）

## 2. 目标
发布 `@workfleet/testkit`：FakeAgent 能以 ACP（JSON-RPC over stdio）回放录制夹具或回声应答，FakeChannel 能按渠道方言（web / wechat_clawbot / feishu）模拟收发与能力限制，FakeRelay 能以 envelope 协议驱动节点测试；三者均有自测。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-NF-009、REQ-NF-008
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-005-中转↔节点协议.md、ADR-007-输入端.md
  - docs/WorkFleet-V0.0.2/30-协议与端点/01-ACP协议深度分析.md（ACP v1 方法：initialize、session/new、session/prompt、session/update、session/request_permission、session/cancel、session/load）
  - docs/WorkFleet-V0.0.2/30-协议与端点/03-输出端接入矩阵.md §1（微信方言：context_token、约 10 条主动额度，部分确认）
- 契约：
  - `packages/contracts/protocol/envelope.schema.json` 与全部 `protocol/frames/*.schema.json`（FakeRelay 发收帧均经 `validateEnvelope()`）
  - `packages/contracts/adapters/channel-capabilities.schema.json`、`adapters/channel-kinds.v1.json`（FakeChannel 方言默认能力：wechat_clawbot `buttons=false`、`proactiveQuota{windowSec:86400,maxMessagesPerInbound:10,tokenTtlSec:86400}`；feishu `cards/buttons/editMessage=true`、`rateLimitPerSec=5`）
  - `packages/contracts/adapters/input-adapter-spec.schema.json`（FakeAgent 以 `adapterId: fake-echo`、`family: acp` 呈现）
  - `packages/contracts/schemas/entities/message-body.schema.json`（FakeChannel 记录的出站内容为 IR 渲染结果）
- 前置任务：TASK-002
- 前置状态：TASK-002 已合并（`@workfleet/contracts` 可 import）

## 4. 输出
- `packages/testkit/package.json`（`@workfleet/testkit`，`bin.fake-acp-agent` → `dist/fake-agent/cli.js`；scripts `test`、`typecheck`、`build`）、`packages/testkit/tsconfig.json`
- `packages/testkit/src/fake-agent/{cli.ts,replayer.ts,echo.ts,recorder.ts}`：回放模式 `--fixture <path.jsonl>`、回声模式 `--echo`（对每个 `session/prompt` 发 `session/update{agent_message_chunk: "echo: <原文>"}` 后以 `stopReason:end_turn` 结束）、`--permission` 选项触发一次 `session/request_permission`；`recorder.ts` 作为 stdio 代理把真实智能体往返录成夹具（供 TASK-022/081 使用）
- `packages/testkit/fixtures/acp/echo/{basic.jsonl,permission.jsonl,cancel.jsonl}` 与 `fixtures/acp/README.md`（夹具格式：每行 `{dir:"c2a"|"a2c", msg:<JSON-RPC>, delayMs?}`；id 回放时重映射；`sessionId` 占位符 `$SESSION`）
- `packages/testkit/src/fake-channel/{index.ts,dialects/web.ts,dialects/wechat-clawbot.ts,dialects/feishu.ts}`：`injectInbound({platformId,text,quoteOf?})`、`outbox()` 捕获、`capabilities`、微信方言按入站刷新 context_token 与额度计数（第 11 条主动消息返回 `CHANNEL_QUOTA_EXHAUSTED`）
- `packages/testkit/src/fake-relay/{server.ts,script.ts}`：WSS 服务端，`expectHello()`、`sendFrame(type,payload)`、`expectAck(upToSeq)`、`dropConnection()`、`replayFrom(seq)`
- `packages/testkit/test/**`（三者自测）

## 5. Execution Steps
1. [ ] 定义夹具格式与 `fixtures/acp/README.md`；写 `echo/basic.jsonl`（initialize→session/new→session/prompt→session/update×2→prompt 响应）、`permission.jsonl`（含 `session/request_permission` options allow_once/reject_once）、`cancel.jsonl`（session/cancel → stopReason cancelled）。
2. [ ] 实现 FakeAgent 回放器：逐行匹配客户端请求的 method（忽略 id 与 sessionId 值），输出对应 a2c 消息；不匹配时以 JSON-RPC error `-32601` 报告并以退出码 1 结束，便于测试定位。
3. [ ] 实现回声模式与 `recorder.ts`（透明代理 stdin/stdout，记录双向消息到 JSONL，敏感字段如 `env`、`authMethods` 中的 token 打码）。
4. [ ] 实现 FakeChannel 基类 + 三个方言：能力取自 `channel-kinds.v1.json`（缺省字段按 capabilities schema 补 false/0）；微信方言维护每接收人 `context_token` 与剩余额度；飞书方言支持按钮回调注入 `injectAction({approvalId, optionId})`。
5. [ ] 实现 FakeRelay：基于 `ws`；所有帧经 `validateEnvelope()`；可脚本化地发帧、断线、校验 ack 与 seq 单调。
6. [ ] 自测：FakeAgent 回放 `basic.jsonl` 全流程、`permission.jsonl` 等待客户端回复后继续；FakeChannel 微信方言第 11 条主动消息失败；FakeRelay 断线后能从指定 seq 续发。
7. [ ] 执行第 7 节命令并保存证据。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`pnpm -F @workfleet/testkit test` 全绿。
- [ ] AC-2：以 `fake-acp-agent --fixture fixtures/acp/echo/basic.jsonl` 为子进程，按 ACP v1 顺序调用 initialize/session/new/session/prompt，收到 `stopReason: end_turn`；调用顺序错误时进程以退出码 1 结束并输出 `-32601`。
- [ ] AC-3：`--echo` 模式下 prompt `"hello"` 收到 `agent_message_chunk` 文本 `"echo: hello"`。
- [ ] AC-4：FakeChannel(wechat_clawbot)：一次入站后连续 10 条主动消息成功、第 11 条返回 `CHANNEL_QUOTA_EXHAUSTED`；再次入站后额度重置；`capabilities.buttons === false`。
- [ ] AC-5：FakeRelay 发出的每一帧和收到的每一帧都通过 `validateEnvelope()`；`dropConnection()` 后客户端以 `lastAckedRelaySeq=k` 重连可收到 seq>k 的帧。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/testkit test
pnpm -F @workfleet/testkit typecheck
pnpm -F @workfleet/testkit build && echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}' | node packages/testkit/dist/fake-agent/cli.js --echo
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-008/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `packages/testkit/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-008/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-008/` 除外）
- `packages/testkit/fixtures/acp/{claude-code,codex,cursor,gemini-cli,qwen-code,kimi-cli,opencode,goose,cline,qoder-cli,github-copilot,openclaw,zcode}/**`（归 TASK-022/081/082/083/084）
- `apps/**`

## 11. 依赖与阻塞
- Depends on：TASK-002
- Blocks：TASK-011, TASK-105
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - ChannelAdapter 端口未在契约中定义（由 TASK-042 在 relay channels 模块内定义）→ FakeChannel 先按 capabilities + 收发最小接口实现；TASK-042 端口签名若不兼容需由 Agent-QA 新任务适配，不在本卡内追改
  - ACP 方法/字段若与 V0.0.2 分析不一致（ACP v2 draft 变动）→ 以 v1 为准；需要 v2 时 blocked
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：测试替身是机械实现，协议已在契约与 ACP v1 分析中确定，sonnect 足够。

## 13. 升级条件
- FakeAgent 回放与真实智能体行为偏差导致下游 TASK-021 测试假绿（真机冒烟失败而回放通过）→ 升 opus 复核夹具匹配策略
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-02）：微信方言的“24h context_token + 每次入站约 10 条”为部分确认值，FakeChannel 以 `channel-kinds.v1.json` 的规划值实现并可配置；真值由 TASK-041 真机验证后回填。
- 假设（NON_BLOCKING，U-05）：ACP TS SDK 包名未定；FakeAgent 直接实现 JSON-RPC，不依赖 SDK。
- 风险：FakeChannel 与 TASK-042 端口定义不同步（契约缺 ChannelAdapter 端口）→ 已列入缺陷汇报。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-008/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
