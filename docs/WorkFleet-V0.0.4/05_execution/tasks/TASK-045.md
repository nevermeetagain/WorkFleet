# TASK-045：delivery：outbox 工作者、令牌桶、重试表、死信、IR 渲染降级、过程消息合并（DEC-017）

```yaml
id: TASK-045
slice: S2
status: todo
owner: Agent-Relay
tier: opus
size: 大
title: "delivery：outbox 工作者、令牌桶、重试表、死信、IR 渲染降级、过程消息合并（DEC-017）"
dependsOn: ["042"]
blocks: ["048", "101", "121", "122", "125", "143", "201"]
reqs: "REQ-NF-001/003"
allowedPaths: ["apps/relay/src/modules/delivery/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-045/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S2
- 来源需求：REQ-NF-001、REQ-NF-003（tasks.v1.json 原值 `REQ-NF-001/003`）
- 来源方案：REQ-NF-001/003（至少一次 + 幂等、重启/断线 10 分钟内恢复不丢不重）、DEC-017（过程消息合并：只回完成/失败/审批/阻塞或可编辑状态卡）、DEC-024（小 IR 按能力渲染）、DEC-023（微信额度不足→合并/降级/提示续期）、architecture §4.1（delivery）

## 2. 目标
delivery 以 `deliveries` 表为 outbox：工作者按渠道令牌桶限速发送、失败按重试表退避、耗尽进死信；发送前把消息 IR 按渠道 capabilities 渲染降级（卡片→Markdown→纯文本，超长拆分），并按 DEC-017 合并/编辑过程消息。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-NF-001、REQ-NF-003、REQ-F-009（额度）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.1、§6.1 第 7 步
  - docs/WorkFleet-V0.0.2/30-协议与端点/03-输出端接入矩阵.md §1（微信 ClawBot / iLink：接口、请求头、限制与证据标签）（各渠道速率与富消息差异）
  - docs/WorkFleet-V0.0.4/04_planning/cost-budget.md §3（本卡默认替代方案：sonnect 执行 + opus review）
- 契约：
  - `packages/contracts/schemas/entities/delivery.schema.json`（status queued|sending|sent|failed|dead|suppressed、attempts、renderedAs card|markdown|text|digest、filtersApplied、lastError、platformMessageId）
  - `packages/contracts/schemas/entities/message-body.schema.json`（IR 块 paragraph/heading/list/code/table/callout/kpi/attachment/approval/status_card）、`message.schema.json`（priority p0–p3）
  - `packages/contracts/adapters/channel-capabilities.schema.json`（editMessage、cards、buttons、markdown、maxMessageChars、rateLimitPerSec、proactiveQuota）
  - `packages/contracts/errors/error-codes.json`：`CHANNEL_QUOTA_EXHAUSTED`（429 可重试）、`CHANNEL_CREDENTIAL_EXPIRED`（409 可重试）、`CHANNEL_CAPABILITY_UNSUPPORTED`（422 不可重试）、`RATE_LIMITED`；`events/domain-events.json`：`delivery.sent`（deliveryId+attempt）、`delivery.failed`（重试耗尽进死信）
  - 表：`deliveries`（`ux_deliveries(message_id, recipient_id)`、`ix_deliveries_due(status, next_attempt_at)`、`rendered_payload`、`next_attempt_at`）、`recipients.quiet_hours`、`channel_tokens`
- 前置任务：TASK-042
- 前置状态：TASK-042 已合并（`channels.getCapabilities()`、`channels.send()`/`edit()`、健康状态）

## 4. 输出
- `apps/relay/src/modules/delivery/domain/{render/**,retry-policy.ts,token-bucket.ts,merge-policy.ts}`：渲染器注册表 `registerBlockRenderer(type, (block, caps) => …)`（供 TASK-047 注册无按钮渠道的审批文本渲染）
- `apps/relay/src/modules/delivery/application/{enqueue.ts,worker.ts,recover.ts}`、`infrastructure/**`、`index.ts`（公开 `enqueue(messageId, recipientIds)`、`renderPreview(messageId|body, recipientId)`（供 dry-run））
- 测试：`apps/relay/tests/unit/modules/delivery/**`、`apps/relay/tests/integration/modules/delivery/**`

## 5. Execution Steps
1. [ ] `enqueue`：每个 (message, recipient) 插入一行（`ux_deliveries` 保证幂等，重复 enqueue 不新增）；`next_attempt_at=now`；静默时段内且 priority 为 p2/p3 → `suppressed`（p0/p1 不受静默限制，本卡假设）。
2. [ ] 渲染：读接收人所属渠道 capabilities；`cards` 为真→card 结构，否则 `markdown` 为真→Markdown，否则纯文本；`table/kpi` 在无卡片时转为对齐文本；按 `maxMessageChars` 拆分为多段；`approval` 块默认渲染摘要，`buttons` 为真时附按钮（选项来自 approval），否则调用已注册的文本渲染器；结果写 `rendered_payload` 与 `renderedAs`。
3. [ ] 过程消息合并（DEC-017）：`kind=status`（或含 `status_card` 块）的消息——渠道 `editMessage` 为真且同会话已有已发送状态卡→调用 `edit()` 更新原消息；否则不单独发送，仅在最终消息前合并为一行进度摘要；final/error/审批类始终发送。
4. [ ] 工作者：轮询 `ix_deliveries_due`；按渠道令牌桶（容量 = `max(1, rateLimitPerSec)`，`rateLimitPerSec=0` 视为 1/s）放行；发送前置 `sending` 并记录尝试；成功→`sent` + `platformMessageId` + 发 `delivery.sent`。
5. [ ] 重试表：可重试错误（error-codes `retryable=true`，含 `CHANNEL_QUOTA_EXHAUSTED`、`RATE_LIMITED`、网络错误）按 5 s、30 s、2 min、10 min、30 min、1 h 退避，第 7 次失败→`dead` + 发 `delivery.failed`；不可重试错误（如 `CHANNEL_CAPABILITY_UNSUPPORTED`）直接 `dead`；`CHANNEL_QUOTA_EXHAUSTED` 在该接收人下一次入站刷新 token 后立即提前重试。
6. [ ] 恢复（REQ-NF-003 不重复外发）：进程重启时，`sending` 且无 `platformMessageId` 的行——渠道能按客户端去重键幂等（能力未声明则视为不能）→重发；否则置 `failed` 并记 `lastError=unknown_after_crash`，等待人工在死信页重放（TASK-143），以“宁可人工确认不重复外发”为原则。
7. [ ] `renderPreview`：不写库，返回渲染结果，供 TASK-044 dry-run 使用。
8. [ ] 测试：幂等 enqueue；三档渲染降级与超长拆分；状态卡在可编辑渠道走 edit、不可编辑渠道合并；令牌桶速率（假时钟下 10 条/5 rps ≈2 s）；重试表与死信；崩溃恢复不重复发送；静默时段 suppressed。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：同一 (message, recipient) enqueue 两次只有 1 行 `deliveries`（REQ-NF-003）。
- [ ] AC-2：渲染测试：同一含 table+approval 的消息，对 feishu 能力（cards+buttons）→`renderedAs=card`；对 telegram 能力（markdown+buttons、无 cards）→`markdown`；对 wechat_clawbot 能力（全否）→`text` 且审批以文本呈现；超过 `maxMessageChars` 的文本被拆分。
- [ ] AC-3：状态消息：editMessage=true 渠道调用 `edit()` 而非新发；editMessage=false 渠道 status 消息不产生独立投递（DEC-017）。
- [ ] AC-4：测试替身渠道持续返回可重试错误 → 第 7 次后 `status=dead` 且发出 `delivery.failed` 1 次；假时钟验证退避间隔符合重试表。
- [ ] AC-5：令牌桶：rateLimitPerSec=5 时 10 条投递在假时钟下耗时 ≥1.8 s；模拟进程在 `sending` 时崩溃重启后，该投递不被自动重复发送（置 failed 待重放）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/relay test tests/unit/modules/delivery tests/integration/modules/delivery
pnpm -F @workfleet/relay typecheck
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-045/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/relay/src/modules/delivery/**`
- 明确写出的测试目录（本模块专属；allowedPaths 未含测试路径，按任务指令 §3 在此显式声明，执行前须经主 Agent 确认）：
  - `apps/relay/tests/unit/modules/delivery/**`
  - `apps/relay/tests/integration/modules/delivery/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-045/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-045/` 除外）
- `apps/relay/src/modules/{channels,routing,approvals,notifications,audit,permissions-filter}/**`（仅经 index 公开 API）
- `apps/web/**`、`apps/node/**`

## 11. 依赖与阻塞
- Depends on：TASK-042
- Blocks：TASK-048, TASK-101, TASK-121, TASK-122, TASK-125, TASK-143, TASK-201
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - TASK-042 的 ChannelAdapter 未提供 `edit()` 或去重键能力位 → DEC-017 编辑路径/崩溃恢复策略退化，登记后按“合并 + 人工重放”实现；若需新增能力位到契约则 blocked
  - 备用渠道切换（REQ-F-030）归 TASK-125，本卡不实现；`CHANNEL_QUOTA_EXHAUSTED` 只做重试/等待
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
opus　理由：tasks.v1.json 冻结为 opus（可靠性核心：不丢不重、能力降级）；cost-budget §3 默认替代为“sonnect 执行 + opus review”以节省 S2 opus 券，用户批准前由主 Agent 二选一。

## 13. 升级条件
- 本卡冻结档位已为 opus：若按替代方案以 sonnect 执行，则重试/恢复相关测试连续 2 次失败即切回 opus 执行
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
大　是否小于 2 小时：否

## 15. 风险与假设
- 假设：重试表间隔、静默时段对 p0/p1 豁免为本卡假设（DESIGN-013/017 文档缺失）。
- 假设（NON_BLOCKING，U-02）：微信额度耗尽时等待下一次入站重试；若实测无额度限制（方案 B）此分支不触发。
- 风险：“不重复外发”与“不丢消息”在崩溃窗口内不可兼得，本卡选择不重复 + 人工重放，需 opus 评审确认。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-045/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
