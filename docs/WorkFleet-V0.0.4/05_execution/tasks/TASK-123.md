# TASK-123：Telegram 适配器

```yaml
id: TASK-123
slice: S6
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Channel
tier: sonnect
size: 中
title: "Telegram 适配器"
dependsOn: ["121"]
blocks: ["126"]
reqs: "REQ-F-013"
allowedPaths: ["apps/relay/src/modules/channels/infrastructure/adapters/telegram/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S6（可演示：QQ/钉钉/Telegram/Discord 收发与审批；渠道断开 60 秒内 p0 告警到备用渠道）
- 来源需求：REQ-F-013
- 来源方案：ADR-010（Telegram：Bot API getUpdates，自写或 MIT 库）、ADR-005；DEC-054

## 2. 目标
Telegram 渠道适配器：getUpdates 长轮询收发，内联按钮（callback_query）审批，并支持向频道群发（通知模式）。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.2/30-协议与端点/03-输出端接入矩阵.md`（§0、§6 Telegram、§7 广播专题）
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §4.1 channels（6 个 IM 适配器 + capabilities + 健康）、§6.1
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-013-输出端-Telegram.md`
  - `docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-010-IM适配器实现来源与许可边界.md`
  - `docs/WorkFleet-V0.0.2/30-协议与端点/04-统一适配器接口设计.md`（§4 OutputAdapter 参考，接口以 TASK-042 实际端口为准）
- 契约：
  - `packages/contracts/adapters/channel-kinds.v1.json`：`telegram` 行（inboundMode long_poll、editMessage true、cards false、buttons true、markdown true、proactiveDirectMessages true、broadcastChannel true）
  - `packages/contracts/adapters/channel-capabilities.schema.json`（14 个必填能力位：inboundMode、editMessage、cards、buttons、markdown、threads、quoteReply、groupChat、broadcastChannel、proactiveDirectMessages、proactiveQuota、rateLimitPerSec、maxMessageChars、attachments）
  - `packages/contracts/schemas/entities/channel.schema.json`（kind、config 按 configSchema 校验且不含明文密钥、credentialRef、health healthy/degraded/expired/disconnected/disabled）、`recipient.schema.json`（scope direct/group/channel）、`delivery.schema.json`（renderedAs card/markdown/text/digest、platformMessageId）
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/adapters/channel`（渠道类型 + configSchema + 默认能力）、`POST /api/v1/channels`、`POST /api/v1/channels/{channelId}/credential`、`POST /api/v1/channels/{channelId}/test`
  - `packages/contracts/errors/error-codes.json`：CHANNEL_CREDENTIAL_EXPIRED、CHANNEL_QUOTA_EXHAUSTED、CHANNEL_CAPABILITY_UNSUPPORTED、RATE_LIMITED、BOT_IDENTITY_CONFLICT、RECIPIENT_UNAUTHORIZED、APPROVAL_EXPIRED、APPROVAL_ALREADY_DECIDED
  - `packages/contracts/events/domain-events.json`：message.received（幂等键 channelId+platformMessageId）、channel.health_changed、delivery.sent/delivery.failed
  - `packages/contracts/commands/im-commands.json`（指令前缀 `/` 与全角 `／`；`Y{n} / N{n}` 审批口令）
  - `database/migrations/relay/0001_init.sql`：`channels`（credential_enc、bot_identity_hash + `ux_channels_bot_identity` 全局唯一、cursor、health）、`recipients`（`ux_recipients_platform`）、`messages`（`ux_messages_platform` 用于回复溯源）、`deliveries`（platform_message_id）
- 前置任务：TASK-121
- 前置状态：TASK-045 delivery 已合并（outbox、令牌桶、IR 渲染降级可用）；TASK-042 ChannelAdapter 端口与注册表可用；TASK-047 审批口令可用

## 4. 输出
- `apps/relay/src/modules/channels/infrastructure/adapters/telegram/`：适配器实现（index.ts 注册一行、client、inbound 解析、outbound 发送、审批交互、健康）
- `apps/relay/src/modules/channels/infrastructure/adapters/telegram/__fixtures__/`：FakePlatform 录制数据（脱敏）
- `apps/relay/src/modules/channels/infrastructure/adapters/telegram/__tests__/`：录制回放单测
- `apps/relay/src/modules/channels/infrastructure/adapters/telegram/__live__/`：真机冒烟用例（默认跳过）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-123/`（license.md、回放测试输出、live-smoke.md（人工验收）、capabilities 实测差异）

## 5. Execution Steps
1. [ ] 许可核查（ADR-010）：确认所用实现来源——Bot API 自写 HTTP 客户端（或 MIT 许可库，择一并记录）——的许可证与版本，写入证据 `license.md`；如需新增 npm 依赖，向 Agent-Guard 提交依赖申请（apps/relay/package.json 不在本任务路径内），批准前用自写 HTTP/WS 客户端占位。
2. [ ] 在 `apps/relay/src/modules/channels/infrastructure/adapters/telegram/` 实现 TASK-042 的 ChannelAdapter 端口骨架：configSchema（随 `GET /api/v1/adapters/channel` 暴露）、凭据只经 channels 核心解密获取、启动/停止、能力声明；能力以 channel-kinds.v1.json 的 `telegram` 行为起点，schema 要求但该行缺失的能力位取保守值（false/null/0）并标“待实测”。
3. [ ] 入站：`getUpdates` 长轮询；与 `setWebhook` 互斥（已确认）——启动时检测到已设置 webhook 则报 BOT_IDENTITY_CONFLICT 类告警而不是自行删除；offset 游标持久化到 channels.cursor；更新在服务器最多保留 24 小时（已确认），停机超过 24 小时的缺口写入健康告警。
4. [ ] 出站：单聊避免 >1 条/秒、群 ≤20 条/分、广播约 30 条/秒（已确认）由 delivery 令牌桶执行；429 带 `retry_after`（已确认）映射为 retryAfter。
5. [ ] 主动触达：用户须先私聊/`/start`（部分确认）；未 /start 的接收人发送失败映射 RECIPIENT_UNAUTHORIZED 类说明并不重试。
6. [ ] 频道群发（通知模式）：recipient.scope=channel，Bot 需为频道管理员；付费广播（allow_paid_broadcast）门槛两处官方说法不一致（部分确认），v1 不启用。编辑消息能力（契约 editMessage=true）接入矩阵未覆盖，待实测。
7. [ ] 审批：内联键盘按钮 → callback_query → approvals 公开 API，处理后 answerCallbackQuery 并编辑原消息为结果态；无按钮场景保留 `Y{n}/N{n}`。
8. [ ] 健康与身份：连接/鉴权状态映射为 channel.health（healthy/degraded/expired/disconnected）并经 channels 核心发出 channel.health_changed；凭据失效映射 CHANNEL_CREDENTIAL_EXPIRED；从平台取得 Bot 身份写 bot_identity_hash，冲突交由核心返回 BOT_IDENTITY_CONFLICT（DEC-034）。
9. [ ] FakePlatform 录制回放：在 `apps/relay/src/modules/channels/infrastructure/adapters/telegram/__fixtures__/` 保存脱敏的平台往返（入站事件、发送请求/响应、回调、错误/限流响应），在 `apps/relay/src/modules/channels/infrastructure/adapters/telegram/__tests__/` 用本地 Fake 服务回放，覆盖收、发、审批回调、限流退避、断线重连、凭据失效。
10. [ ] 编写 `apps/relay/src/modules/channels/infrastructure/adapters/telegram/__live__/` 真机冒烟用例（仅在 `WF_LIVE_TELEGRAM=1` 时运行，CI 跳过），并按 §7 人工验收项执行一次，结果写入证据。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] FakePlatform 回放测试全部通过（CI 不依赖真实平台与凭据）
- [ ] 适配器声明的能力通过 channel-capabilities.schema.json 校验（14 个必填位齐全）
- [ ] 同一平台消息重复投递只产生 1 条 message.received（幂等键 channelId+platformMessageId）
- [ ] callback_query 审批回放：approved 后编辑原消息；重复点击返回 APPROVAL_ALREADY_DECIDED
- [ ] getUpdates offset 持久化：重启后不重复处理已确认的 update（回放断言）
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过；fixtures 经 gitleaks 无密钥

## 7. 验证命令
```bash
pnpm --filter @workfleet/relay exec vitest run src/modules/channels/infrastructure/adapters/telegram
pnpm --filter @workfleet/relay exec tsc --noEmit
pnpm exec gitleaks detect --no-git --source apps/relay/src/modules/channels/infrastructure/adapters/telegram/__fixtures__ --redact
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/relay/src/modules/channels/infrastructure/adapters/telegram/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-123/)' || echo 'SCOPE OK'
```

**人工验收项（需要真实凭据，不进 CI）**
```bash
# 真实凭据只放在执行者本机环境变量，不入库、不入证据
WF_LIVE_TELEGRAM=1 WF_TELEGRAM_BOT_TOKEN=<token> WF_TELEGRAM_TEST_CHAT=<chat_id> WF_TELEGRAM_TEST_CHANNEL=<@channel> \
  pnpm --filter @workfleet/relay exec vitest run src/modules/channels/infrastructure/adapters/telegram/__live__
```
- 判断标准：PASS = (1) 测试账号 /start 后私聊消息到达中转并收到回复；(2) 内联按钮审批成功且原消息被编辑为结果态（编辑失败则记录并把 editMessage 实测为 false）；(3) 向测试频道群发 1 条成功；(4) 人为制造 429（短时连发）时观察到 retry_after 被遵守。
- 结论（PASS/FAIL + 截图/消息 id，已脱敏）写入证据 `live-smoke.md`；平台限额类事实只记录实测现象，不覆盖接入矩阵的证据标签。

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-123/
- `README.md`：结论与环境
- `license.md`：实现来源、许可、版本（ADR-010）
- `test-output.txt`：§7 自动化命令输出
- `live-smoke.md`：人工验收项结果（脱敏）
- `capabilities-diff.md`：契约默认能力 vs 实测能力，供 Agent-Contract 同步 channel-kinds.v1.json

## 9. 允许修改
- `apps/relay/src/modules/channels/infrastructure/adapters/telegram/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-123/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/relay/src/modules/channels/** 中本适配器目录以外的部分（核心属 TASK-042，其他适配器属各自任务）
- apps/relay/src/modules/delivery/**、routing/**、approvals/**（只经公开 API 调用）
- packages/testkit/**（FakeChannel 属 Agent-QA；本适配器的 FakePlatform 数据放在适配器目录内）

## 11. 依赖与阻塞
- Depends on：TASK-121
- Blocks：TASK-126
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 所需 SDK/库许可不兼容 Apache-2.0 或依赖申请未获 Agent-Guard 批准且自写成本超出规模 → blocked，写明替代方案（ADR-010：改自写，不阻塞其他渠道）
  - TASK-042 端口缺少本渠道必需的能力回调（如按钮回调入口、消息编辑）→ 停止，不在核心目录内改
  - THIRD_PARTY_NOTICES 文件不在任何任务的允许路径中：许可结论先写证据，并登记跟进项
  - 已有 webhook 设置导致 getUpdates 不可用，且用户要求保留 webhook → 规划裁决

## 12. 建议执行档位
sonnect　理由：Bot API 简单、事实已确认，主力档。

## 13. 升级条件
- 需要 webhook 模式（公网入口）→ 升 opus 出 ADR
- 频道群发规模需要付费广播 → 用户裁决成本

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- 接入矩阵 §6（部分确认）：Bot 不能主动发起对话，依据为 API 错误观测而非方法页原文。
- 接入矩阵 §6（部分确认）：付费广播门槛 Bot API 页与 FAQ 不一致。
- U-03（NON_BLOCKING）：外部订阅者走 Telegram 的假设依赖本适配器的频道群发能力。
- 依赖异常：tasks.v1.json 中 123 依赖 121（QQ），二者无技术依赖，推断为同一 Agent-Channel 串行安排。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - Agent-Contract：按 capabilities-diff.md 同步 channel-kinds.v1.json（该文件各行缺 threads/quoteReply/groupChat/maxMessageChars/attachments 等 schema 必填位）
  - Agent-Guard：新增依赖与 THIRD_PARTY_NOTICES 条目
  - 规划：123→121、124→122 的依赖仅为串行排班，建议在 dag.md 注明，避免误读为技术依赖

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-123/
- 验证者结论：
- 遗留问题 / 跟进项编号：
