# TASK-125：notifications：p0–p3、渠道健康告警、备用渠道

```yaml
id: TASK-125
slice: S6
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Relay
tier: sonnect
size: 中
title: "notifications：p0–p3、渠道健康告警、备用渠道"
dependsOn: ["045"]
blocks: ["126", "203", "207"]
reqs: "REQ-F-030"
allowedPaths: ["apps/relay/src/modules/notifications/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S6（可演示：QQ/钉钉/Telegram/Discord 收发与审批；渠道断开 60 秒内 p0 告警到备用渠道）
- 来源需求：REQ-F-030
- 来源方案：DEC-023、G7；architecture §4.1 notifications（p0–p3、渠道健康告警、备用渠道）

## 2. 目标
中转 notifications 模块实现 p0–p3 分级通知与渠道健康告警：凭据失效、额度将尽、长连接断开在 60 秒内产生 p0 告警，并在主渠道不可用时经备用渠道送达。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §4.1 notifications、§6.1 第 7 步（额度不足提示续期）
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-030-通知分级与渠道健康.md`
  - `docs/WorkFleet-V0.0.4/00_governance/glossary.md`（优先级 p0 立即、p1 高、p2 普通、p3 摘要）
  - `docs/WorkFleet-V0.0.2/30-协议与端点/03-输出端接入矩阵.md` §1.3 设计应对（额度剩 ≤3 条提示续期、降级到其它渠道）、§11 风险（必须有备用渠道）
- 契约：
  - `packages/contracts/events/domain-events.json`：channel.health_changed（幂等键 channelId+health+at）、delivery.failed、device.offline
  - `packages/contracts/schemas/entities/channel.schema.json`：health healthy/degraded/expired/disconnected/disabled；`recipient.schema.json` quietHours、linkedUserId
  - `packages/contracts/errors/error-codes.json`：CHANNEL_CREDENTIAL_EXPIRED、CHANNEL_QUOTA_EXHAUSTED
  - `packages/contracts/adapters/channel-capabilities.schema.json`：proactiveQuota（maxMessagesPerInbound 等）
  - `packages/contracts/protocol/frames/agent.output.schema.json`：priority p0–p3
  - `database/migrations/relay/0001_init.sql`：`channels.health`、`channel_tokens.sent_since_refresh`（额度计数）、`recipients`、`deliveries`、`push_subscriptions.min_priority`（Web Push 由 TASK-203 实现）
- 前置任务：TASK-045
- 前置状态：TASK-045 delivery 已合并；各渠道适配器经 channels 核心发出 channel.health_changed（TASK-042）

## 4. 输出
- `apps/relay/src/modules/notifications/domain/`：优先级策略（p0 立即且穿透静默时段、p1 高、p2 普通、p3 合并为摘要）
- `apps/relay/src/modules/notifications/application/`：notify()、健康告警订阅器、备用渠道选择、p3 摘要合并
- `apps/relay/src/modules/notifications/index.ts`、`__tests__/`
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-125/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 定义 notify(tenant, priority, payload) 公开 API；p3 进入摘要缓冲，p2 按普通 delivery，p1/p0 立即入队；p0 穿透 recipients.quietHours，其他级别遵守。
2. [ ] 订阅 channel.health_changed：expired → p0“凭据失效”；disconnected 持续 → p0“长连接断开”；degraded → p1；恢复 healthy → p2 恢复通知；同一渠道同一状态去重。
3. [ ] 额度将尽：订阅 delivery 侧额度计数（channel_tokens.sent_since_refresh 对比 proactiveQuota.maxMessagesPerInbound），剩余 ≤3 条产生 p0“回复任意字续期”提示（DEC-023）。
4. [ ] 60 秒时限：健康事件到 p0 入队必须 <60 s；断线检测本身由适配器负责，本模块只保证从事件到入队的时延并记录指标。
5. [ ] 备用渠道选择：排除告警所涉渠道，选择同租户内 health=healthy 且有已授权、linkedUserId 指向告警接收人的 direct 接收人的渠道；全部不可用时保留 Web 渠道（站内）并记审计。
6. [ ] p0 不受 p3 摘要合并影响；所有告警写 audit（经 audit 公开 API）。
7. [ ] 写测试（假时钟）：渠道 expired → 60 s 内 p0 经备用渠道入队；静默时段内 p2 延迟、p0 立即；额度剩 3 条提示；重复健康事件不重复告警。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 注入 channel.health_changed(expired) 后 60 s 内（假时钟）产生 1 条 p0 delivery，且其 channelId ≠ 故障渠道
- [ ] 无可用备用渠道时 p0 落到 Web 渠道并有审计记录
- [ ] 同一渠道连续 5 次相同健康事件只产生 1 条告警
- [ ] 静默时段内 p2 被延迟、p0 立即发送
- [ ] 额度剩余 ≤3 条时产生续期提示（p0）
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过

## 7. 验证命令
```bash
pnpm --filter @workfleet/relay exec vitest run src/modules/notifications --exclude "src/modules/notifications/infrastructure/webpush/**"
pnpm --filter @workfleet/relay exec tsc --noEmit
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/relay/src/modules/notifications/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-125/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-125/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `apps/relay/src/modules/notifications/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-125/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/relay/src/modules/notifications/infrastructure/webpush/**（TASK-203 所有，虽在本任务 glob 内也不得写）
- apps/relay/src/modules/channels/**（health 由适配器/核心产生）
- apps/relay/src/modules/delivery/**

## 11. 依赖与阻塞
- Depends on：TASK-045
- Blocks：TASK-126, TASK-203, TASK-207
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 契约与迁移 0001 中都没有“备用渠道”的配置字段或表：本卡按上述推断规则自动选择；若需用户可配置（REQ-F-030 未明确），停止并请求 Agent-Contract/Agent-Data 出 ADR + 迁移
  - delivery 未暴露额度剩余数的读取 API（额度计数在 channel_tokens，由 TASK-041/045 维护）
  - audit 模块公开 API 尚不存在（TASK-143 在 S7）→ 先记录运行日志并登记，不阻塞

## 12. 建议执行档位
sonnect　理由：订阅事件 + 策略表，规则明确，可用假时钟完全测试。

## 13. 升级条件
- 需要新增备用渠道配置（契约/表）→ 升 opus 出 ADR
- p0 告警时延在集成环境超过 60 s → 升 opus 排查跨模块链路

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- U-02（BLOCKING，仅 REQ-F-009 提醒策略）：额度将尽提示依赖 `capabilities.proactiveQuota`；若 U-02 判定无限制，proactiveQuota=null，本模块自动不产生额度告警。
- U-07（NON_BLOCKING）：Web Push 在 iOS 的行为未知；本任务不实现 Web Push（TASK-203），只把 p0/p1 交给其公开 API（若已存在）。
- 假设（推断）：备用渠道 = 同租户其他健康渠道上与告警接收人同一用户的已授权私聊接收人。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - Agent-Contract/Agent-Data：缺少备用渠道与通知偏好的契约字段/端点与表（仅有 push_subscriptions.min_priority）
  - 规划：TASK-125 的 allowedPaths `notifications/**` 覆盖 TASK-203 的 webpush/**，靠依赖顺序避免冲突；125 未依赖 041（微信额度计数）

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-125/
- 验证者结论：
- 遗留问题 / 跟进项编号：
