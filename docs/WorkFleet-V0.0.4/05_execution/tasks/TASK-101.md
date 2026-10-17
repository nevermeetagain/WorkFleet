# TASK-101：飞书/Lark 适配器：长连接、卡片、按钮、卡片更新、双域

```yaml
id: TASK-101
slice: S5
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Channel
tier: sonnect
size: 大
title: "飞书/Lark 适配器：长连接、卡片、按钮、卡片更新、双域"
dependsOn: ["045"]
blocks: ["105", "126"]
reqs: "REQ-F-010"
allowedPaths: ["apps/relay/src/modules/channels/infrastructure/adapters/feishu/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S5（可演示：场景 2——三个来源汇总后分别发给老板与数据部；通知模式两人回话分会话）
- 来源需求：REQ-F-010
- 来源方案：ADR-010（飞书/Lark：官方 Node SDK 长连接）、ADR-005、ADR-006；DEC-035、G16；REQ-C-004（不与 OpenClaw 共用同一飞书应用）

## 2. 目标
飞书/Lark 渠道适配器：同一实现按配置连接 feishu.cn 或 larksuite.com，经长连接收消息，发送文本/卡片，卡片按钮完成审批，并对过程消息做卡片流式更新。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.2/30-协议与端点/03-输出端接入矩阵.md`（§0 一页结论、§2 飞书/Lark、§8、§10 结论 Y）
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §4.1 channels（6 个 IM 适配器 + capabilities + 健康）、§6.1
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-010-输出端-飞书Lark.md`
  - `docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-010-IM适配器实现来源与许可边界.md`
  - `docs/WorkFleet-V0.0.2/30-协议与端点/04-统一适配器接口设计.md`（§4 OutputAdapter 参考，接口以 TASK-042 实际端口为准）
- 契约：
  - `packages/contracts/adapters/channel-kinds.v1.json`：`feishu` 行（inboundMode websocket、editMessage/cards/buttons/markdown true、proactiveDirectMessages true、rateLimitPerSec 5、notes“feishu.cn / larksuite.com 双域”）
  - `packages/contracts/adapters/channel-capabilities.schema.json`（14 个必填能力位：inboundMode、editMessage、cards、buttons、markdown、threads、quoteReply、groupChat、broadcastChannel、proactiveDirectMessages、proactiveQuota、rateLimitPerSec、maxMessageChars、attachments）
  - `packages/contracts/schemas/entities/channel.schema.json`（kind、config 按 configSchema 校验且不含明文密钥、credentialRef、health healthy/degraded/expired/disconnected/disabled）、`recipient.schema.json`（scope direct/group/channel）、`delivery.schema.json`（renderedAs card/markdown/text/digest、platformMessageId）
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/adapters/channel`（渠道类型 + configSchema + 默认能力）、`POST /api/v1/channels`、`POST /api/v1/channels/{channelId}/credential`、`POST /api/v1/channels/{channelId}/test`
  - `packages/contracts/errors/error-codes.json`：CHANNEL_CREDENTIAL_EXPIRED、CHANNEL_QUOTA_EXHAUSTED、CHANNEL_CAPABILITY_UNSUPPORTED、RATE_LIMITED、BOT_IDENTITY_CONFLICT、RECIPIENT_UNAUTHORIZED、APPROVAL_EXPIRED、APPROVAL_ALREADY_DECIDED
  - `packages/contracts/events/domain-events.json`：message.received（幂等键 channelId+platformMessageId）、channel.health_changed、delivery.sent/delivery.failed
  - `packages/contracts/commands/im-commands.json`（指令前缀 `/` 与全角 `／`；`Y{n} / N{n}` 审批口令）
  - `database/migrations/relay/0001_init.sql`：`channels`（credential_enc、bot_identity_hash + `ux_channels_bot_identity` 全局唯一、cursor、health）、`recipients`（`ux_recipients_platform`）、`messages`（`ux_messages_platform` 用于回复溯源）、`deliveries`（platform_message_id）
  - `packages/contracts/protocol/frames/approval.request|approval.decision`（审批经中转 approvals 模块转回节点）
- 前置任务：TASK-045
- 前置状态：TASK-045 delivery 已合并（outbox、令牌桶、IR 渲染降级可用）；TASK-042 ChannelAdapter 端口与注册表可用；TASK-047 审批口令可用

## 4. 输出
- `apps/relay/src/modules/channels/infrastructure/adapters/feishu/`：适配器实现（index.ts 注册一行、client、inbound 解析、outbound 发送、审批交互、健康）
- `apps/relay/src/modules/channels/infrastructure/adapters/feishu/__fixtures__/`：FakePlatform 录制数据（脱敏）
- `apps/relay/src/modules/channels/infrastructure/adapters/feishu/__tests__/`：录制回放单测
- `apps/relay/src/modules/channels/infrastructure/adapters/feishu/__live__/`：真机冒烟用例（默认跳过）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-101/`（license.md、回放测试输出、live-smoke.md（人工验收）、capabilities 实测差异）

## 5. Execution Steps
1. [ ] 许可核查（ADR-010）：确认所用实现来源——飞书官方 Node SDK（包名与许可待核）——的许可证与版本，写入证据 `license.md`；如需新增 npm 依赖，向 Agent-Guard 提交依赖申请（apps/relay/package.json 不在本任务路径内），批准前用自写 HTTP/WS 客户端占位。
2. [ ] 在 `apps/relay/src/modules/channels/infrastructure/adapters/feishu/` 实现 TASK-042 的 ChannelAdapter 端口骨架：configSchema（随 `GET /api/v1/adapters/channel` 暴露）、凭据只经 channels 核心解密获取、启动/停止、能力声明；能力以 channel-kinds.v1.json 的 `feishu` 行为起点，schema 要求但该行缺失的能力位取保守值（false/null/0）并标“待实测”。
3. [ ] 双域：config 增加 `domain`（feishu|lark）决定开放平台基地址，同一代码路径；长连接只适用企业自建应用（接入矩阵 §2，已确认），配置向导文案需说明。
4. [ ] 入站：订阅 `im.message.receive_v1`（已确认），先持久化再在 3 秒内完成 ACK（长连接收到后 3 秒内处理完否则重推，已确认）；长连接为集群模式（多客户端随机一个收到，已确认），中转单实例运行，不得同应用多实例。
5. [ ] 出站：`POST /open-apis/im/v1/messages`；同一用户/同一群 5 QPS、接口 1000 次/分 & 50 次/秒（已确认）由 delivery 令牌桶执行，本适配器把限流响应转换为 retryAfter；卡片 JSON ≤30KB（已确认），超出降级为 markdown。
6. [ ] 卡片流式更新：CardKit 创建 `streaming_mode: true` 卡片实体并流式更新文本（已确认）；发送后 14 天内可更新（已确认）；交互回调前须先关闭流式（已确认）。
7. [ ] 审批：审批卡片按钮 → `card.action.trigger` 回调须 3 秒内响应（已确认），先 ACK 再异步调用 approvals 公开 API；回调能否经长连接送达为“证据不足”，必须在真机冒烟中实测：若不能，按钮渲染关闭并降级为 `Y{n}/N{n}` 文本口令，结论写入 capabilities-diff.md。
8. [ ] 健康与身份：连接/鉴权状态映射为 channel.health（healthy/degraded/expired/disconnected）并经 channels 核心发出 channel.health_changed；凭据失效映射 CHANNEL_CREDENTIAL_EXPIRED；从平台取得 Bot 身份写 bot_identity_hash，冲突交由核心返回 BOT_IDENTITY_CONFLICT（DEC-034）。
9. [ ] FakePlatform 录制回放：在 `apps/relay/src/modules/channels/infrastructure/adapters/feishu/__fixtures__/` 保存脱敏的平台往返（入站事件、发送请求/响应、回调、错误/限流响应），在 `apps/relay/src/modules/channels/infrastructure/adapters/feishu/__tests__/` 用本地 Fake 服务回放，覆盖收、发、审批回调、限流退避、断线重连、凭据失效。
10. [ ] 编写 `apps/relay/src/modules/channels/infrastructure/adapters/feishu/__live__/` 真机冒烟用例（仅在 `WF_LIVE_FEISHU=1` 时运行，CI 跳过），并按 §7 人工验收项执行一次，结果写入证据。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] FakePlatform 回放测试全部通过（CI 不依赖真实平台与凭据）
- [ ] 适配器声明的能力通过 channel-capabilities.schema.json 校验（14 个必填位齐全）
- [ ] 同一平台消息重复投递只产生 1 条 message.received（幂等键 channelId+platformMessageId）
- [ ] 审批卡片回调回放：approved 后卡片更新为结果态；过期返回 APPROVAL_EXPIRED 并置灰（回放断言）
- [ ] domain=feishu 与 domain=lark 两组回放分别命中各自基地址
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过；fixtures 经 gitleaks 无密钥

## 7. 验证命令
```bash
pnpm --filter @workfleet/relay exec vitest run src/modules/channels/infrastructure/adapters/feishu
pnpm --filter @workfleet/relay exec tsc --noEmit
pnpm exec gitleaks detect --no-git --source apps/relay/src/modules/channels/infrastructure/adapters/feishu/__fixtures__ --redact
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/relay/src/modules/channels/infrastructure/adapters/feishu/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-101/)' || echo 'SCOPE OK'
```

**人工验收项（需要真实凭据，不进 CI）**
```bash
# 真实凭据只放在执行者本机环境变量，不入库、不入证据
WF_LIVE_FEISHU=1 WF_FEISHU_DOMAIN=feishu WF_FEISHU_APP_ID=<id> WF_FEISHU_APP_SECRET=<secret> WF_FEISHU_TEST_CHAT=<chat_id> \
  pnpm --filter @workfleet/relay exec vitest run src/modules/channels/infrastructure/adapters/feishu/__live__
```
- 判断标准：PASS = (1) 在飞书客户端发消息，60 秒内中转产生 message.received；(2) 适配器发出的卡片在客户端可见；(3) 点击审批按钮后审批状态变为 approved 且卡片更新为结果态（若长连接收不到回调，则记为“回调需 HTTPS”FAIL 并验证 Y1 口令可用）；(4) 流式更新卡片可见至少 3 次文本变化；(5) 切换 WF_FEISHU_DOMAIN=lark 用 Lark 应用重复 (1)(2)（无 Lark 测试租户则该项记 UNKNOWN）。
- 结论（PASS/FAIL + 截图/消息 id，已脱敏）写入证据 `live-smoke.md`；平台限额类事实只记录实测现象，不覆盖接入矩阵的证据标签。

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-101/
- `README.md`：结论与环境
- `license.md`：实现来源、许可、版本（ADR-010）
- `test-output.txt`：§7 自动化命令输出
- `live-smoke.md`：人工验收项结果（脱敏）
- `capabilities-diff.md`：契约默认能力 vs 实测能力，供 Agent-Contract 同步 channel-kinds.v1.json

## 9. 允许修改
- `apps/relay/src/modules/channels/infrastructure/adapters/feishu/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-101/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/relay/src/modules/channels/** 中本适配器目录以外的部分（核心属 TASK-042，其他适配器属各自任务）
- apps/relay/src/modules/delivery/**、routing/**、approvals/**（只经公开 API 调用）
- packages/testkit/**（FakeChannel 属 Agent-QA；本适配器的 FakePlatform 数据放在适配器目录内）

## 11. 依赖与阻塞
- Depends on：TASK-045
- Blocks：TASK-105, TASK-126
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 所需 SDK/库许可不兼容 Apache-2.0 或依赖申请未获 Agent-Guard 批准且自写成本超出规模 → blocked，写明替代方案（ADR-010：改自写，不阻塞其他渠道）
  - TASK-042 端口缺少本渠道必需的能力回调（如按钮回调入口、消息编辑）→ 停止，不在核心目录内改
  - THIRD_PARTY_NOTICES 文件不在任何任务的允许路径中：许可结论先写证据，并登记跟进项
  - 卡片回调无法走长连接且需要中转公网 HTTPS 回调端点：relay.openapi 中无该端点，停止并请求 Agent-Contract 新增（需 ADR）

## 12. 建议执行档位
sonnect　理由：体量大但遵循既定端口与官方 SDK，事实均有已确认来源；回调路径不确定性有明确降级方案。

## 13. 升级条件
- 卡片回调必须走 HTTPS → 升 opus 出 ADR 并转 Agent-Contract
- 流式更新与 delivery 的过程消息合并（DEC-017）冲突 → 升 opus 仲裁

## 14. 预估规模
大(≈2d)　是否小于 2 小时：否

## 15. 风险与假设
- U-03（NON_BLOCKING）：假设飞书机器人不能主动触达租户外用户；外部订阅者走 Telegram，本任务不实现跨租户。
- 接入矩阵 §10 结论 Y（证据不足）：卡片回调走长连接未确认，需实测；兜底需中转 HTTPS 回调。
- 接入矩阵 §2（部分确认）：一个应用 = 一个 Bot，多产品线需多个应用，对应多个 channel 实例。
- REQ-C-004/DEC-034：与 OpenClaw 等共用同一飞书应用会导致消息被随机一方收到（集群模式），由 bot_identity_hash 唯一约束阻断。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - Agent-Contract：按 capabilities-diff.md 同步 channel-kinds.v1.json（该文件各行缺 threads/quoteReply/groupChat/maxMessageChars/attachments 等 schema 必填位）
  - Agent-Guard：新增依赖与 THIRD_PARTY_NOTICES 条目
  - Agent-Contract：飞书卡片回调若需 HTTPS，relay.openapi 缺少渠道回调端点

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-101/
- 验证者结论：
- 遗留问题 / 跟进项编号：
