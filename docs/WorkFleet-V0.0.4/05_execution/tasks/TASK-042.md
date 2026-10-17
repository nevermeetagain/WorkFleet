# TASK-042：channels 核心：ChannelAdapter 端口、注册表、capabilities、凭据加密、健康状态

```yaml
id: TASK-042
slice: S2
status: todo
owner: Agent-Relay
tier: opus
size: 中
title: "channels 核心：ChannelAdapter 端口、注册表、capabilities、凭据加密、健康状态"
dependsOn: ["010"]
blocks: ["041", "043", "045"]
reqs: "REQ-NF-008"
allowedPaths: ["apps/relay/src/modules/channels/** (除 infrastructure/adapters/*)"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-042/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S2
- 来源需求：REQ-NF-008（tasks.v1.json 原值 `REQ-NF-008`）
- 来源方案：REQ-NF-008（新增一个 IM = 新增一个 channel 适配器目录 + 注册一行，核心零改动）、DEC-008（按能力降级，不写渠道特判）、ADR-010、architecture §4.1（channels：凭据加密、capabilities、健康）、DESIGN-007（组件/端口，文档未落地）

## 2. 目标
channels 核心提供 ChannelAdapter 端口、自动发现的适配器注册表、capabilities 合成、凭据加密存储、Bot 身份唯一性与健康状态机，以及渠道管理 HTTP 端点；核心代码中不出现任何渠道特判。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.1、§6.1
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-010-IM适配器实现来源与许可边界.md
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-NF-008、REQ-C-004、REQ-F-030
  - docs/WorkFleet-V0.0.2/30-协议与端点/03-输出端接入矩阵.md §1（微信 ClawBot / iLink：接口、请求头、限制与证据标签）（各渠道能力差异）
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`GET/POST /api/v1/channels`（channel.read/write；`VALIDATION_FAILED`、`BOT_IDENTITY_CONFLICT`）、`DELETE /api/v1/channels/{channelId}`、`GET /api/v1/adapters/channel`、`POST /api/v1/channels/{channelId}/credential`（`{secret}`，204，不回显，channel.bind_credential）、`POST /api/v1/channels/{channelId}/qr-login`、`GET /api/v1/channels/{channelId}/qr-login/{loginId}`、`POST /api/v1/channels/{channelId}/test`
  - `packages/contracts/schemas/entities/channel.schema.json`（kind、config、credentialRef、capabilities、health healthy|degraded|expired|disconnected|disabled）、`adapters/channel-capabilities.schema.json`（14 个必填能力位）、`adapters/channel-kinds.v1.json`（7 种渠道默认能力）
  - `packages/contracts/errors/error-codes.json`：`BOT_IDENTITY_CONFLICT`、`CHANNEL_CAPABILITY_UNSUPPORTED`（422）、`CHANNEL_CREDENTIAL_EXPIRED`；`events/domain-events.json`：`channel.health_changed`、`message.received`
  - 表：`channels`（`credential_enc` BLOB、`bot_identity_hash` + `ux_channels_bot_identity`、`capabilities` JSON、`health`、`cursor`、version）、`channel_tokens`
- 前置任务：TASK-010
- 前置状态：TASK-010 已合并（Web 渠道适配器位于 `adapters/web/**`，channels 目录已存在）

## 4. 输出
- `apps/relay/src/modules/channels/domain/{ports/channel-adapter.ts,capabilities.ts,health.ts}`：`ChannelAdapter{kind; capabilities(); start(ctx); stop(); send(rendered, recipient) → {platformMessageId}; edit?(platformMessageId, rendered); startQrLogin?(); pollQrLogin?(loginId)}`；`ctx` 提供 `emitInbound(event)`、`setHealth()`、`credentials`、`tokens`、`cursor`
- `apps/relay/src/modules/channels/infrastructure/{registry.ts,crypto.ts,persistence/**}`：`registry.ts` 自动发现 `infrastructure/adapters/*/index.ts`（每个导出 `{kind, create}`），并在非生产环境额外加载 `WF_RELAY_TEST_ADAPTER_MODULES` 指定的模块（供 TASK-048 注入 FakeChannel）；`crypto.ts` AES-256-GCM，主密钥来自 `WF_RELAY_MASTER_KEY_FILE`
- `apps/relay/src/modules/channels/application/**`（创建/删除渠道、提交凭据、扫码委派、测试发送、启动/停止适配器、入站分发 `onInbound(handler)` 扩展点）、`interfaces/http/**`
- `apps/relay/src/modules/channels/index.ts`（公开 `getAdapter(channelId)`、`getCapabilities(channelId)`、`onInbound()`、`send()`）
- 测试：`apps/relay/tests/unit/modules/channels/**`、`apps/relay/tests/integration/modules/channels/**`（不含 adapters 子目录）

## 5. Execution Steps
1. [ ] 定义 ChannelAdapter 端口与 capabilities 合成：`channel-kinds.v1.json` 的规划值 → 按 capabilities schema 补齐缺省（布尔 false、数值 0、`proactiveQuota` null）→ 叠加适配器运行时声明；结果存 `channels.capabilities` 并通过 schema 校验。
2. [ ] 注册表：启动时扫描 `adapters/*/index.ts`；kind 重复即启动失败；`WF_RELAY_TEST_ADAPTER_MODULES` 在 `NODE_ENV=production` 时被拒绝。核对 TASK-010 的 `adapters/web` 是否满足端口；不满足时不修改它，登记缺陷并 blocked 该兼容项。
3. [ ] 凭据：`POST /credential` 的 `secret` 用 AES-256-GCM（随机 IV，附 channelId 作为 AAD）加密写 `credential_enc`，响应 204 不回显；日志与错误体不得含 secret；渠道读取接口只返回 `credentialRef`（非空表示已绑定）。
4. [ ] Bot 身份：适配器在凭据确认后上报 bot 身份，核心计算 `bot_identity_hash`；唯一索引冲突→409 `BOT_IDENTITY_CONFLICT`（跨组织全局唯一，DEC-034）。
5. [ ] 健康状态机：disabled→（启动）healthy；适配器上报 degraded/expired/disconnected；每次变化写库并发 `channel.health_changed{channelId, health, at}`（幂等键 channelId+health+at）。
6. [ ] HTTP 端点：创建（config 按 `GET /adapters/channel` 返回的 configSchema 校验）、删除（停止适配器、软删除）、qr-login 委派（适配器未实现→422 `CHANNEL_CAPABILITY_UNSUPPORTED`）、test（经 `send()` 发固定文本）。
7. [ ] 入站分发：适配器 `emitInbound({channelId, platformMessageId, platformId, scope, displayName, text, quoteOfPlatformMessageId?})` → 进程内去重（channelId+platformMessageId 的 LRU）→ 依次调用 `onInbound` 订阅者（TASK-043 授权、TASK-044 路由）。
8. [ ] 测试：用测试替身适配器验证自动发现与“新增目录即生效”；凭据加密往返与不回显；Bot 身份冲突；健康事件；qr-login 不支持返回 422；源码扫描断言核心目录无 `wechat|feishu|qq|dingtalk|telegram|discord` 字面量特判。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：在 `adapters/` 下放入一个测试替身适配器目录（仅 `index.ts`）即被注册，核心零改动（REQ-NF-008）。
- [ ] AC-2：`POST /channels/{id}/credential` → 204；`channels.credential_enc` 为密文、`GET /channels` 不含 secret；`grep` 日志无 secret 明文。
- [ ] AC-3：两个组织绑定同一 bot 身份 → 第二个返回 409 `BOT_IDENTITY_CONFLICT`。
- [ ] AC-4：适配器上报 expired → `channels.health=expired` 且发出 `channel.health_changed` 事件 1 次。
- [ ] AC-5：不支持扫码的渠道调 `qr-login` → 422 `CHANNEL_CAPABILITY_UNSUPPORTED`；所有渠道的 capabilities 通过 `channel-capabilities.schema.json`。
- [ ] AC-6：核心目录（`channels/{domain,application,interfaces,infrastructure/registry.ts}`）中无渠道名字面量分支（脚本断言）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/relay test tests/unit/modules/channels tests/integration/modules/channels
pnpm -F @workfleet/relay typecheck
! grep -rnE "'(wechat|wechat_clawbot|feishu|qq|dingtalk|telegram|discord)'" apps/relay/src/modules/channels/{domain,application,interfaces} apps/relay/src/modules/channels/infrastructure/registry.ts
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-042/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/relay/src/modules/channels/** (除 infrastructure/adapters/*)`
- 明确写出的测试目录（本模块专属；allowedPaths 未含测试路径，按任务指令 §3 在此显式声明，执行前须经主 Agent 确认）：
  - `apps/relay/tests/unit/modules/channels/**（不含 adapters/**）`
  - `apps/relay/tests/integration/modules/channels/**（不含 adapters/**）`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-042/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-042/` 除外）
- `apps/relay/src/modules/channels/infrastructure/adapters/*/**`（含 `web/**` 归 TASK-010、`wechat-clawbot/**` 归 TASK-041、其余归 S5/S6 渠道任务）
- `apps/relay/src/modules/channels/application/identity-guard/**`（TASK-207）
- `apps/relay/src/modules/{delivery,recipients,routing,notifications}/**`

## 11. 依赖与阻塞
- Depends on：TASK-010
- Blocks：TASK-041, TASK-043, TASK-045
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - TASK-010 的 Web 渠道适配器与本卡端口不兼容，而本卡不得改 `adapters/web/**` → 登记缺陷，blocked 该兼容项，由主 Agent 另立迁移任务
  - ChannelAdapter 端口不在契约中（只存在于 relay 内部），TASK-008 FakeChannel 已先行实现 → 签名不一致时需 Agent-QA 新任务适配，不在本卡改 testkit
  - 迁移中没有“原始入站事件”表（architecture §6.1 要求“立即持久化入站事件”）→ 本卡以内存 LRU 去重，崩溃窗口内可能丢入站；需新增表则交 Agent-Data（blocked）
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
opus　理由：端口一经确定，6 个 IM 适配器（S2/S5/S6）都依赖它，属不可轻易回滚的跨模块接口；同时涉及凭据加密，按 opus 执行。

## 13. 升级条件
- 本卡已为 opus：若端口需要进入契约包（跨进程复用）或推翻 DEC-008 → 升 fable 并 blocked
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-03）：飞书不能主动触达租户外用户，端口不为此预留能力位（外部订阅者走 Telegram）。
- 风险：`channel-kinds.v1.json` 各条目缺 capabilities schema 的多个必填位（threads、quoteReply、groupChat、rateLimitPerSec、maxMessageChars、attachments 等）→ 以缺省补齐，可能低估能力；已报告。
- 风险：主密钥文件丢失将导致全部渠道凭据不可解密 → 运维文档（TASK-209）需覆盖备份。
- DESIGN-007 文档缺失，端口签名为本卡设计，需 opus 评审定稿后冻结。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-042/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
