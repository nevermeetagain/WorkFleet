# TASK-121：QQ 官方机器人适配器

```yaml
id: TASK-121
slice: S6
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Channel
tier: sonnect
size: 中
title: "QQ 官方机器人适配器"
dependsOn: ["045"]
blocks: ["123"]
reqs: "REQ-F-011"
allowedPaths: ["apps/relay/src/modules/channels/infrastructure/adapters/qq/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S6（可演示：QQ/钉钉/Telegram/Discord 收发与审批；渠道断开 60 秒内 p0 告警到备用渠道）
- 来源需求：REQ-F-011
- 来源方案：ADR-010（QQ：官方开放平台 WebSocket，自写客户端）、ADR-005；DEC-054；R-06

## 2. 目标
QQ 官方机器人适配器：经开放平台 WebSocket 收单聊与群 @ 消息，优先在被动回复窗口内回复，主动消息受平台配额与用户开关约束并按能力降级。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.2/30-协议与端点/03-输出端接入矩阵.md`（§0、§3 QQ 官方机器人、§7、§9 What if）
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §4.1 channels（6 个 IM 适配器 + capabilities + 健康）、§6.1
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-011-输出端-QQ.md`
  - `docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-010-IM适配器实现来源与许可边界.md`
  - `docs/WorkFleet-V0.0.2/30-协议与端点/04-统一适配器接口设计.md`（§4 OutputAdapter 参考，接口以 TASK-042 实际端口为准）
- 契约：
  - `packages/contracts/adapters/channel-kinds.v1.json`：`qq` 行（inboundMode websocket、editMessage false、cards/buttons/markdown true、proactiveDirectMessages true、notes“主动消息配额文档冲突（R-06）”）
  - `packages/contracts/adapters/channel-capabilities.schema.json`（14 个必填能力位：inboundMode、editMessage、cards、buttons、markdown、threads、quoteReply、groupChat、broadcastChannel、proactiveDirectMessages、proactiveQuota、rateLimitPerSec、maxMessageChars、attachments）
  - `packages/contracts/schemas/entities/channel.schema.json`（kind、config 按 configSchema 校验且不含明文密钥、credentialRef、health healthy/degraded/expired/disconnected/disabled）、`recipient.schema.json`（scope direct/group/channel）、`delivery.schema.json`（renderedAs card/markdown/text/digest、platformMessageId）
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/adapters/channel`（渠道类型 + configSchema + 默认能力）、`POST /api/v1/channels`、`POST /api/v1/channels/{channelId}/credential`、`POST /api/v1/channels/{channelId}/test`
  - `packages/contracts/errors/error-codes.json`：CHANNEL_CREDENTIAL_EXPIRED、CHANNEL_QUOTA_EXHAUSTED、CHANNEL_CAPABILITY_UNSUPPORTED、RATE_LIMITED、BOT_IDENTITY_CONFLICT、RECIPIENT_UNAUTHORIZED、APPROVAL_EXPIRED、APPROVAL_ALREADY_DECIDED
  - `packages/contracts/events/domain-events.json`：message.received（幂等键 channelId+platformMessageId）、channel.health_changed、delivery.sent/delivery.failed
  - `packages/contracts/commands/im-commands.json`（指令前缀 `/` 与全角 `／`；`Y{n} / N{n}` 审批口令）
  - `database/migrations/relay/0001_init.sql`：`channels`（credential_enc、bot_identity_hash + `ux_channels_bot_identity` 全局唯一、cursor、health）、`recipients`（`ux_recipients_platform`）、`messages`（`ux_messages_platform` 用于回复溯源）、`deliveries`（platform_message_id）
- 前置任务：TASK-045
- 前置状态：TASK-045 delivery 已合并（outbox、令牌桶、IR 渲染降级可用）；TASK-042 ChannelAdapter 端口与注册表可用；TASK-047 审批口令可用

## 4. 输出
- `apps/relay/src/modules/channels/infrastructure/adapters/qq/`：适配器实现（index.ts 注册一行、client、inbound 解析、outbound 发送、审批交互、健康）
- `apps/relay/src/modules/channels/infrastructure/adapters/qq/__fixtures__/`：FakePlatform 录制数据（脱敏）
- `apps/relay/src/modules/channels/infrastructure/adapters/qq/__tests__/`：录制回放单测
- `apps/relay/src/modules/channels/infrastructure/adapters/qq/__live__/`：真机冒烟用例（默认跳过）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-121/`（license.md、回放测试输出、live-smoke.md（人工验收）、capabilities 实测差异）

## 5. Execution Steps
1. [ ] 许可核查（ADR-010）：确认所用实现来源——自写 WebSocket/HTTP 客户端（ADR-010 指定，不引入社区 SDK）——的许可证与版本，写入证据 `license.md`；如需新增 npm 依赖，向 Agent-Guard 提交依赖申请（apps/relay/package.json 不在本任务路径内），批准前用自写 HTTP/WS 客户端占位。
2. [ ] 在 `apps/relay/src/modules/channels/infrastructure/adapters/qq/` 实现 TASK-042 的 ChannelAdapter 端口骨架：configSchema（随 `GET /api/v1/adapters/channel` 暴露）、凭据只经 channels 核心解密获取、启动/停止、能力声明；能力以 channel-kinds.v1.json 的 `qq` 行为起点，schema 要求但该行缺失的能力位取保守值（false/null/0）并标“待实测”。
3. [ ] 入站：控制台需切到 WebSocket 方式（可与 Webhook 切换且立即生效，已确认）；处理 `C2C_MESSAGE_CREATE`、`GROUP_AT_MESSAGE_CREATE`（群内需 @ 机器人），以及 `C2C_MSG_REJECT/RECEIVE`、`GROUP_MSG_REJECT/RECEIVE`（用户关闭/开启主动消息，已确认）并记录到接收人状态。
4. [ ] 被动回复：单聊消息 60 分钟内有效、每条最多回复 4 次；群聊 5 分钟、5 次；以 msg_id/event_id 标识（已确认）。适配器优先用被动回复，窗口外才走主动消息。
5. [ ] 主动消息：新版页给出单聊/群聊 QPS 与每好友/每群每天 ≤1000 条（已确认，新版页），旧版页写“每月 4 条”（文档冲突，部分确认，R-06）——配额值不写死，可配置并以控制台实际配额为准；用户关闭主动消息或配额耗尽 → CHANNEL_QUOTA_EXHAUSTED，由 notifications 走备用渠道。
6. [ ] 富消息：msg_type 0 文本 / 2 Markdown / 3 Ark / 7 富媒体（已确认）；Markdown/按钮等高阶能力常需申请（部分确认），未获权限时能力位关闭并降级为纯文本，不报错。
7. [ ] 审批：有按钮权限时渲染按钮，否则（默认）降级为 `Y{n}/N{n}` 文本口令（TASK-047）；按钮权限是否获批为“待实测”。
8. [ ] 健康与身份：连接/鉴权状态映射为 channel.health（healthy/degraded/expired/disconnected）并经 channels 核心发出 channel.health_changed；凭据失效映射 CHANNEL_CREDENTIAL_EXPIRED；从平台取得 Bot 身份写 bot_identity_hash，冲突交由核心返回 BOT_IDENTITY_CONFLICT（DEC-034）。
9. [ ] FakePlatform 录制回放：在 `apps/relay/src/modules/channels/infrastructure/adapters/qq/__fixtures__/` 保存脱敏的平台往返（入站事件、发送请求/响应、回调、错误/限流响应），在 `apps/relay/src/modules/channels/infrastructure/adapters/qq/__tests__/` 用本地 Fake 服务回放，覆盖收、发、审批回调、限流退避、断线重连、凭据失效。
10. [ ] 编写 `apps/relay/src/modules/channels/infrastructure/adapters/qq/__live__/` 真机冒烟用例（仅在 `WF_LIVE_QQ=1` 时运行，CI 跳过），并按 §7 人工验收项执行一次，结果写入证据。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] FakePlatform 回放测试全部通过（CI 不依赖真实平台与凭据）
- [ ] 适配器声明的能力通过 channel-capabilities.schema.json 校验（14 个必填位齐全）
- [ ] 同一平台消息重复投递只产生 1 条 message.received（幂等键 channelId+platformMessageId）
- [ ] 被动窗口内回复走 msg_id 回复；窗口外走主动发送；用户关闭主动消息后返回 CHANNEL_QUOTA_EXHAUSTED（回放断言）
- [ ] 无 Markdown 权限时 renderedAs=text，不抛 CHANNEL_CAPABILITY_UNSUPPORTED 给用户
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过；fixtures 经 gitleaks 无密钥

## 7. 验证命令
```bash
pnpm --filter @workfleet/relay exec vitest run src/modules/channels/infrastructure/adapters/qq
pnpm --filter @workfleet/relay exec tsc --noEmit
pnpm exec gitleaks detect --no-git --source apps/relay/src/modules/channels/infrastructure/adapters/qq/__fixtures__ --redact
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/relay/src/modules/channels/infrastructure/adapters/qq/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-121/)' || echo 'SCOPE OK'
```

**人工验收项（需要真实凭据，不进 CI）**
```bash
# 真实凭据只放在执行者本机环境变量，不入库、不入证据
WF_LIVE_QQ=1 WF_QQ_APP_ID=<appid> WF_QQ_SECRET=<secret> WF_QQ_TEST_OPENID=<user_openid> WF_QQ_TEST_GROUP=<group_openid> \
  pnpm --filter @workfleet/relay exec vitest run src/modules/channels/infrastructure/adapters/qq/__live__
```
- 判断标准：PASS = (1) 单聊发消息后中转收到并在被动窗口内回复成功；(2) 测试群 @ 机器人后收到并回复；(3) 用 Y1 完成一次审批；(4) 记录一次主动消息（窗口外）的实际结果与控制台显示的配额值（用于判定 R-06）；(5) 在客户端关闭主动消息后再次主动发送，得到 CHANNEL_QUOTA_EXHAUSTED 映射。
- 结论（PASS/FAIL + 截图/消息 id，已脱敏）写入证据 `live-smoke.md`；平台限额类事实只记录实测现象，不覆盖接入矩阵的证据标签。

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-121/
- `README.md`：结论与环境
- `license.md`：实现来源、许可、版本（ADR-010）
- `test-output.txt`：§7 自动化命令输出
- `live-smoke.md`：人工验收项结果（脱敏）
- `capabilities-diff.md`：契约默认能力 vs 实测能力，供 Agent-Contract 同步 channel-kinds.v1.json

## 9. 允许修改
- `apps/relay/src/modules/channels/infrastructure/adapters/qq/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-121/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/relay/src/modules/channels/** 中本适配器目录以外的部分（核心属 TASK-042，其他适配器属各自任务）
- apps/relay/src/modules/delivery/**、routing/**、approvals/**（只经公开 API 调用）
- packages/testkit/**（FakeChannel 属 Agent-QA；本适配器的 FakePlatform 数据放在适配器目录内）

## 11. 依赖与阻塞
- Depends on：TASK-045
- Blocks：TASK-123
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 所需 SDK/库许可不兼容 Apache-2.0 或依赖申请未获 Agent-Guard 批准且自写成本超出规模 → blocked，写明替代方案（ADR-010：改自写，不阻塞其他渠道）
  - TASK-042 端口缺少本渠道必需的能力回调（如按钮回调入口、消息编辑）→ 停止，不在核心目录内改
  - THIRD_PARTY_NOTICES 文件不在任何任务的允许路径中：许可结论先写证据，并登记跟进项
  - 控制台实际配额与两版文档均不一致且影响 REQ-F-011 验收口径 → 记录证据并请规划裁决

## 12. 建议执行档位
sonnect　理由：自写客户端但协议面小、事实已确认，冲突点以可配置吸收，主力档。

## 13. 升级条件
- R-06 实测结果要求改变产品口径（QQ 不再支持主动消息）→ 升 opus 并由用户裁决
- 需要实现 WebSocket 鉴权/心跳的非文档化细节 → 升 opus 评审

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- R-06（部分确认）：QQ 主动消息配额文档冲突（新版每天 1000 条 vs 旧版每月 4 条），若以每月 4 条为准则 QQ 降级为仅被动回复渠道（接入矩阵 §9）。
- 接入矩阵 §3（已确认）：用户可在客户端关闭主动消息，关闭后主动消息一律失败。
- 接入矩阵 §3（部分确认）：Markdown/Ark 等高阶能力常需申请（社区称门槛较高）。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - Agent-Contract：按 capabilities-diff.md 同步 channel-kinds.v1.json（该文件各行缺 threads/quoteReply/groupChat/maxMessageChars/attachments 等 schema 必填位）
  - Agent-Guard：新增依赖与 THIRD_PARTY_NOTICES 条目
  - Agent-Contract：channel-kinds.v1.json 的 qq 行 cards/buttons=true，但按钮/Markdown 需平台审批，默认值宜为 false 或注明条件

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-121/
- 验证者结论：
- 遗留问题 / 跟进项编号：
