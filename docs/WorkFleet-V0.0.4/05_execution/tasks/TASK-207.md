# TASK-207：Bot 唯一消费者检测与告警

```yaml
id: TASK-207
slice: S10
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Relay
tier: sonnect
size: 小
title: "Bot 唯一消费者检测与告警"
dependsOn: ["125"]
blocks: ["208"]
reqs: "REQ-F-031"
allowedPaths: ["apps/relay/src/modules/channels/application/identity-guard/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S10
- 来源需求：REQ-F-031
- 来源方案：DEC-034（一个 Bot 身份只允许一个消费者）；REQ-C-004；REQ-F-031；DEC-023（健康告警走备用渠道）

## 2. 目标
在配置时阻止同一 Bot 身份被第二个渠道使用（`BOT_IDENTITY_CONFLICT`），在运行时根据适配器上报的冲突信号（被顶掉、getUpdates 冲突、消息序号缺口等）检测“同一 Bot 被他处消费”，并发出 p0 告警到备用渠道。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-031、REQ-C-004）
  - docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md（DEC-034、DEC-023）
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-010-IM适配器实现来源与许可边界.md
- 契约：
  - packages/contracts/errors/error-codes.json：`BOT_IDENTITY_CONFLICT`（409，ui：向导阻断 + 说明）
  - packages/contracts/events/domain-events.json：`channel.health_changed`
  - packages/contracts/adapters/channel-capabilities.schema.json、adapters/channel-kinds.v1.json（各渠道能力与身份字段）
  - packages/contracts/api/relay.openapi.json：`POST /api/v1/channels/{channelId}/credential`（凭据提交时检测）
  - database/migrations/relay/0001_init.sql：`channels.bot_identity_hash`（唯一索引 `ux_channels_bot_identity`，跨组织全局唯一）、`channels.health`
- 前置任务：TASK-125
- 前置状态：TASK-125 notifications（p0、备用渠道）已合并；TASK-042 ChannelAdapter 端口与健康状态已合并。

## 4. 输出
- apps/relay/src/modules/channels/application/identity-guard/（computeBotIdentityHash、配置时冲突检查、运行时冲突判定器、告警触发）
- apps/relay/src/modules/channels/application/identity-guard/__tests__/
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-207/`（见 §8）

## 5. Execution Steps
1. [ ] 配置时：凭据提交后按渠道类型计算稳定身份（如 app id / bot id 的 SHA-256，不含密钥）→ 写入前查唯一索引 → 冲突返回 409 `BOT_IDENTITY_CONFLICT`（跨组织冲突不得泄露对方组织信息）。
2. [ ] 运行时信号表：逐渠道整理“被他处消费”的可观测信号并标证据等级——如 Telegram Bot API 在并发 getUpdates 时返回冲突错误（部分确认，待适配器实测）；微信 iLink、飞书长连接、钉钉 Stream、QQ、Discord 的对应行为**证据不足**，以 TASK-041/101/121–124 的真机记录为准；写入 EVD。
3. [ ] 判定器：订阅 `channel.health_changed` 与适配器上报的冲突原因码，结合“入站序号缺口/长时间无入站但平台侧有活动”启发式，产出 `identity_conflict` 判定（去抖：同一渠道 10 分钟内只告警一次，推断）。
4. [ ] 告警：调用 notifications 发 p0（走备用渠道），文案说明 DEC-034 约束与处理建议（如关闭 ZCode 自带微信 Bot、不与 OpenClaw 共用飞书应用）。
5. [ ] 写测试：FakeChannel 两个渠道配置同一 bot id → 第二个 409；FakeChannel 注入 Telegram 方言冲突错误 → 60 s 内 p0 告警到备用渠道；去抖。
6. [ ] 运行验证命令并存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 同一 Bot 身份第二次绑定返回 409 `BOT_IDENTITY_CONFLICT`，且响应不含另一组织信息（测试）。
- [ ] FakeChannel 注入冲突信号后 60 s 内备用渠道收到 1 条 p0 告警（测试，假时钟）。
- [ ] 10 分钟内重复信号不重复告警。
- [ ] 身份哈希不含也不可逆推出凭据（只用公开 id 计算，单测）。
- [ ] `make guard` 通过。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-207/
pnpm --filter ./apps/relay exec vitest run src/modules/channels/application/identity-guard --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-207/vitest.txt
pnpm --filter ./apps/relay exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-207/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-207/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-207/
- `vitest.txt`、`tsc.txt`、`guard.txt`
- `signal-table.md`（每渠道冲突信号、证据等级、来源）

## 9. 允许修改
- `apps/relay/src/modules/channels/application/identity-guard/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-207/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-207/` 除外，见 ownership-matrix §4）
- apps/relay/src/modules/channels/infrastructure/adapters/**（Agent-Channel 所有）
- apps/relay/src/modules/channels/ 下除 application/identity-guard 外文件
- apps/relay/src/modules/notifications/**

## 11. 依赖与阻塞
- Depends on：TASK-125
- Blocks：TASK-208
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - ChannelAdapter 端口（TASK-042）没有上报“身份冲突”原因码的通道：运行时检测只能靠启发式 → 报接口缺口，配置时检测仍交付。
  - 平台对“被他处消费”无任何可观测信号（证据不足）的渠道：在信号表中标“不可检测”，不臆造。

## 12. 建议执行档位
sonnect　理由：配置时唯一性已由索引保证；运行时判定为事件订阅 + 去抖。

## 13. 升级条件
- 需要修改 ChannelAdapter 端口或 capabilities 契约增加冲突信号 → opus 契约审。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
小　是否小于 2 小时：否

## 15. 风险与假设
- 证据不足：多数渠道的冲突信号。
- 假设：去抖窗口 10 分钟（推断）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-207/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-207.md`）
