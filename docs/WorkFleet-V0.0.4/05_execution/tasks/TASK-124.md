# TASK-124：Discord 适配器

```yaml
id: TASK-124
slice: S6
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Channel
tier: sonnect
size: 中
title: "Discord 适配器"
dependsOn: ["122"]
blocks: ["126"]
reqs: "REQ-F-014"
allowedPaths: ["apps/relay/src/modules/channels/infrastructure/adapters/discord/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S6（可演示：QQ/钉钉/Telegram/Discord 收发与审批；渠道断开 60 秒内 p0 告警到备用渠道）
- 来源需求：REQ-F-014
- 来源方案：ADR-010（Discord：Gateway，Apache-2.0 库）、ADR-005；DEC-054

## 2. 目标
Discord 渠道适配器：经 Gateway 收发频道与私信消息，按钮组件完成审批，支持频道消息群发。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.2/30-协议与端点/03-输出端接入矩阵.md`（§0、§5 Discord、§7）
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §4.1 channels（6 个 IM 适配器 + capabilities + 健康）、§6.1
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-014-输出端-Discord.md`
  - `docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-010-IM适配器实现来源与许可边界.md`
  - `docs/WorkFleet-V0.0.2/30-协议与端点/04-统一适配器接口设计.md`（§4 OutputAdapter 参考，接口以 TASK-042 实际端口为准）
- 契约：
  - `packages/contracts/adapters/channel-kinds.v1.json`：`discord` 行（inboundMode websocket、editMessage/cards/buttons/markdown/proactiveDirectMessages true、broadcastChannel true）
  - `packages/contracts/adapters/channel-capabilities.schema.json`（14 个必填能力位：inboundMode、editMessage、cards、buttons、markdown、threads、quoteReply、groupChat、broadcastChannel、proactiveDirectMessages、proactiveQuota、rateLimitPerSec、maxMessageChars、attachments）
  - `packages/contracts/schemas/entities/channel.schema.json`（kind、config 按 configSchema 校验且不含明文密钥、credentialRef、health healthy/degraded/expired/disconnected/disabled）、`recipient.schema.json`（scope direct/group/channel）、`delivery.schema.json`（renderedAs card/markdown/text/digest、platformMessageId）
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/adapters/channel`（渠道类型 + configSchema + 默认能力）、`POST /api/v1/channels`、`POST /api/v1/channels/{channelId}/credential`、`POST /api/v1/channels/{channelId}/test`
  - `packages/contracts/errors/error-codes.json`：CHANNEL_CREDENTIAL_EXPIRED、CHANNEL_QUOTA_EXHAUSTED、CHANNEL_CAPABILITY_UNSUPPORTED、RATE_LIMITED、BOT_IDENTITY_CONFLICT、RECIPIENT_UNAUTHORIZED、APPROVAL_EXPIRED、APPROVAL_ALREADY_DECIDED
  - `packages/contracts/events/domain-events.json`：message.received（幂等键 channelId+platformMessageId）、channel.health_changed、delivery.sent/delivery.failed
  - `packages/contracts/commands/im-commands.json`（指令前缀 `/` 与全角 `／`；`Y{n} / N{n}` 审批口令）
  - `database/migrations/relay/0001_init.sql`：`channels`（credential_enc、bot_identity_hash + `ux_channels_bot_identity` 全局唯一、cursor、health）、`recipients`（`ux_recipients_platform`）、`messages`（`ux_messages_platform` 用于回复溯源）、`deliveries`（platform_message_id）
- 前置任务：TASK-122
- 前置状态：TASK-045 delivery 已合并（outbox、令牌桶、IR 渲染降级可用）；TASK-042 ChannelAdapter 端口与注册表可用；TASK-047 审批口令可用

## 4. 输出
- `apps/relay/src/modules/channels/infrastructure/adapters/discord/`：适配器实现（index.ts 注册一行、client、inbound 解析、outbound 发送、审批交互、健康）
- `apps/relay/src/modules/channels/infrastructure/adapters/discord/__fixtures__/`：FakePlatform 录制数据（脱敏）
- `apps/relay/src/modules/channels/infrastructure/adapters/discord/__tests__/`：录制回放单测
- `apps/relay/src/modules/channels/infrastructure/adapters/discord/__live__/`：真机冒烟用例（默认跳过）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-124/`（license.md、回放测试输出、live-smoke.md（人工验收）、capabilities 实测差异）

## 5. Execution Steps
1. [ ] 许可核查（ADR-010）：确认所用实现来源——Apache-2.0 许可的 Discord Gateway 库（具体库与版本待核）——的许可证与版本，写入证据 `license.md`；如需新增 npm 依赖，向 Agent-Guard 提交依赖申请（apps/relay/package.json 不在本任务路径内），批准前用自写 HTTP/WS 客户端占位。
2. [ ] 在 `apps/relay/src/modules/channels/infrastructure/adapters/discord/` 实现 TASK-042 的 ChannelAdapter 端口骨架：configSchema（随 `GET /api/v1/adapters/channel` 暴露）、凭据只经 channels 核心解密获取、启动/停止、能力声明；能力以 channel-kinds.v1.json 的 `discord` 行为起点，schema 要求但该行缺失的能力位取保守值（false/null/0）并标“待实测”。
3. [ ] 入站：Gateway WebSocket（已确认）；`MESSAGE_CONTENT` 为特权 Intent，未获批时 content/embeds/attachments/components 为空（DM、@提及除外，已确认）——启动时检测并在健康状态与向导中提示。
4. [ ] 限流：全局 50 请求/秒且应读响应头而非硬编码（已确认）；Gateway 每连接 120 事件/60 秒；IDENTIFY 1000 次/24h，超限会重置 token（已确认）——重连必须优先 RESUME，IDENTIFY 计数写入健康指标。
5. [ ] 出站：content ≤2000 字符、embeds ≤10（部分确认）——maxMessageChars 取 2000，超长分段或转附件；2500 服务器以上必须分片（已确认），v1 不实现分片，超限时健康为 degraded。
6. [ ] 私信：DM 触达条件为“证据不足”，以真机冒烟结果为准；频道消息用于通知模式群发（recipient.scope=channel）。
7. [ ] 审批：按钮组件 → Interaction → approvals 公开 API，并更新原消息为结果态；Interaction 的响应时限接入矩阵未覆盖，待实测，先 ACK（deferred）再处理。
8. [ ] 健康与身份：连接/鉴权状态映射为 channel.health（healthy/degraded/expired/disconnected）并经 channels 核心发出 channel.health_changed；凭据失效映射 CHANNEL_CREDENTIAL_EXPIRED；从平台取得 Bot 身份写 bot_identity_hash，冲突交由核心返回 BOT_IDENTITY_CONFLICT（DEC-034）。
9. [ ] FakePlatform 录制回放：在 `apps/relay/src/modules/channels/infrastructure/adapters/discord/__fixtures__/` 保存脱敏的平台往返（入站事件、发送请求/响应、回调、错误/限流响应），在 `apps/relay/src/modules/channels/infrastructure/adapters/discord/__tests__/` 用本地 Fake 服务回放，覆盖收、发、审批回调、限流退避、断线重连、凭据失效。
10. [ ] 编写 `apps/relay/src/modules/channels/infrastructure/adapters/discord/__live__/` 真机冒烟用例（仅在 `WF_LIVE_DISCORD=1` 时运行，CI 跳过），并按 §7 人工验收项执行一次，结果写入证据。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] FakePlatform 回放测试全部通过（CI 不依赖真实平台与凭据）
- [ ] 适配器声明的能力通过 channel-capabilities.schema.json 校验（14 个必填位齐全）
- [ ] 同一平台消息重复投递只产生 1 条 message.received（幂等键 channelId+platformMessageId）
- [ ] 超过 2000 字的消息被分段发送（回放断言）；断线重连优先 RESUME，IDENTIFY 次数计数正确
- [ ] 未授予 MESSAGE_CONTENT 时健康为 degraded 并给出说明
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过；fixtures 经 gitleaks 无密钥

## 7. 验证命令
```bash
pnpm --filter @workfleet/relay exec vitest run src/modules/channels/infrastructure/adapters/discord
pnpm --filter @workfleet/relay exec tsc --noEmit
pnpm exec gitleaks detect --no-git --source apps/relay/src/modules/channels/infrastructure/adapters/discord/__fixtures__ --redact
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/relay/src/modules/channels/infrastructure/adapters/discord/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-124/)' || echo 'SCOPE OK'
```

**人工验收项（需要真实凭据，不进 CI）**
```bash
# 真实凭据只放在执行者本机环境变量，不入库、不入证据
WF_LIVE_DISCORD=1 WF_DISCORD_BOT_TOKEN=<token> WF_DISCORD_TEST_CHANNEL=<channel_id> WF_DISCORD_TEST_USER=<user_id> \
  pnpm --filter @workfleet/relay exec vitest run src/modules/channels/infrastructure/adapters/discord/__live__
```
- 判断标准：PASS = (1) 测试频道 @ 机器人与普通消息（若有 MESSAGE_CONTENT 权限）到达中转；(2) 按钮审批成功并更新原消息；(3) 频道消息群发 1 条成功；(4) 向测试用户发 DM 的结果被记录（成功或失败原因，用于关闭“DM 条件证据不足”）；(5) 断开网络 30 秒后恢复，日志显示 RESUME 而非 IDENTIFY。
- 结论（PASS/FAIL + 截图/消息 id，已脱敏）写入证据 `live-smoke.md`；平台限额类事实只记录实测现象，不覆盖接入矩阵的证据标签。

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-124/
- `README.md`：结论与环境
- `license.md`：实现来源、许可、版本（ADR-010）
- `test-output.txt`：§7 自动化命令输出
- `live-smoke.md`：人工验收项结果（脱敏）
- `capabilities-diff.md`：契约默认能力 vs 实测能力，供 Agent-Contract 同步 channel-kinds.v1.json

## 9. 允许修改
- `apps/relay/src/modules/channels/infrastructure/adapters/discord/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-124/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/relay/src/modules/channels/** 中本适配器目录以外的部分（核心属 TASK-042，其他适配器属各自任务）
- apps/relay/src/modules/delivery/**、routing/**、approvals/**（只经公开 API 调用）
- packages/testkit/**（FakeChannel 属 Agent-QA；本适配器的 FakePlatform 数据放在适配器目录内）

## 11. 依赖与阻塞
- Depends on：TASK-122
- Blocks：TASK-126
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 所需 SDK/库许可不兼容 Apache-2.0 或依赖申请未获 Agent-Guard 批准且自写成本超出规模 → blocked，写明替代方案（ADR-010：改自写，不阻塞其他渠道）
  - TASK-042 端口缺少本渠道必需的能力回调（如按钮回调入口、消息编辑）→ 停止，不在核心目录内改
  - THIRD_PARTY_NOTICES 文件不在任何任务的允许路径中：许可结论先写证据，并登记跟进项
  - 所选库许可不是 Apache-2.0/MIT 或需要拷贝 AGPL 代码 → 改自写，规模超出则 blocked

## 12. 建议执行档位
sonnect　理由：成熟库 + 已确认限流事实，按端口实现，主力档。

## 13. 升级条件
- 需要分片（>2500 服务器）或 HTTP Interactions 端点 → 升 opus 出 ADR
- IDENTIFY 配额被耗尽导致 token 重置 → 升 opus 评审重连策略

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- 接入矩阵 §5（证据不足）：Discord DM 条件未核。
- 接入矩阵 §5（部分确认）：消息字符与 embed 上限来自第三方 OpenAPI 描述。
- 无 U-xx 直接关联。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - Agent-Contract：按 capabilities-diff.md 同步 channel-kinds.v1.json（该文件各行缺 threads/quoteReply/groupChat/maxMessageChars/attachments 等 schema 必填位）
  - Agent-Guard：新增依赖与 THIRD_PARTY_NOTICES 条目

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-124/
- 验证者结论：
- 遗留问题 / 跟进项编号：
