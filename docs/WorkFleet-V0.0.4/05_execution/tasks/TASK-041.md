# TASK-041：微信 ClawBot 适配器：扫码登录、getupdates、sendmessage、context_token 持久化、额度预算器；真机验证 U-02/U-04

```yaml
id: TASK-041
slice: S2
status: todo
owner: Agent-Channel
tier: opus
size: 大
title: "微信 ClawBot 适配器：扫码登录、getupdates、sendmessage、context_token 持久化、额度预算器；真机验证 U-02/U-04"
dependsOn: ["042"]
blocks: ["048", "126"]
reqs: "REQ-F-009"
allowedPaths: ["apps/relay/src/modules/channels/infrastructure/adapters/wechat-clawbot/**", "docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-041/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-041/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S2
- 来源需求：REQ-F-009（tasks.v1.json 原值 `REQ-F-009`）
- 来源方案：ADR-010（微信 ClawBot：iLink HTTP 长轮询 clean-room，不拷贝代码）、REQ-F-009、REQ-C-004/008、architecture §6.1（微信管理模式流程）、U-02/U-04（product-requirements §7）

## 2. 目标
实现 `wechat_clawbot` 渠道适配器：控制台扫码一次完成绑定，长轮询 `getupdates` 收消息、`sendmessage` 回发，按接收人加密持久化 `context_token`，以额度预算器约束主动消息并在剩余 ≤3 条时提示续期；并在真机上验证 U-02（token 有效期与额度）与 U-04（香港中转访问 iLink 的 RTT 与失败率）。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.2/30-协议与端点/03-输出端接入矩阵.md §1（微信 ClawBot / iLink：接口、请求头、限制与证据标签）
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-010-IM适配器实现来源与许可边界.md
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-009、REQ-F-030（凭据失效 p0）、REQ-C-004/008、§5 第 4 条（不用微信群发）、§7 U-02/U-04
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §6.1
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`POST /api/v1/channels/{channelId}/qr-login`（201 `{qrImageDataUrl, loginId, expiresAt}`）、`GET /api/v1/channels/{channelId}/qr-login/{loginId}`（state waiting|scanned|confirmed|expired|failed）——端点由 TASK-042 实现，本卡实现适配器侧能力
  - `packages/contracts/adapters/channel-kinds.v1.json`（`wechat_clawbot`：inboundMode long_poll、buttons/cards/markdown/editMessage=false、proactiveQuota{windowSec:86400,maxMessagesPerInbound:10,tokenTtlSec:86400}，标注“社区实测，部分确认”）、`adapters/channel-capabilities.schema.json`（分叉点 `proactiveQuota`：U-02 方案 A 有值 / 方案 B 为 null）
  - `packages/contracts/errors/error-codes.json`：`CHANNEL_CREDENTIAL_EXPIRED`（409，重新扫码）、`CHANNEL_QUOTA_EXHAUSTED`（429，回复任意字续期/走备用渠道）、`BOT_IDENTITY_CONFLICT`（409，DEC-034）
  - `packages/contracts/events/domain-events.json`：`channel.health_changed`（凭据失效→p0 告警由 TASK-125 消费）
  - 表：`channels`（`credential_enc`、`bot_identity_hash`（`ux_channels_bot_identity` 全局唯一）、`cursor` 存 `get_updates_buf`、`health`）、`channel_tokens`（channel_id+recipient_id、`token_enc`、`refreshed_at`、`sent_since_refresh`）
- 前置任务：TASK-042
- 前置状态：TASK-042 已合并（ChannelAdapter 端口、注册表自动发现 `infrastructure/adapters/*/index.ts`、凭据加密服务、健康状态机、qr-login 端点委派）；真机验证需用户提供已启用 ClawBot 能力的个人微信（product-requirements §8，部分确认）与可访问的香港中转

## 4. 输出
- `apps/relay/src/modules/channels/infrastructure/adapters/wechat-clawbot/{index.ts,adapter.ts,ilink-client.ts,qr-login.ts,poller.ts,sender.ts,quota-budget.ts,mapper.ts}`
- `ilink-client.ts`：基址 `https://ilinkai.weixin.qq.com`（或扫码确认返回的 `baseurl`）；请求头 `AuthorizationType: ilink_bot_token`、`Authorization: Bearer <bot_token>`、每次新生成的 `X-WECHAT-UIN: base64(随机 uint32)`；接口 `GET ilink/bot/get_bot_qrcode?bot_type=3`、`GET ilink/bot/get_qrcode_status?qrcode=`、`POST ilink/bot/getupdates`、`POST ilink/bot/sendmessage`
- `quota-budget.ts`：按 (channel, recipient) 计算剩余额度 = `maxMessagesPerInbound - sent_since_refresh`、token 过期 = `refreshed_at + tokenTtlSec`；`proactiveQuota=null` 时关闭（U-02 方案 B）
- 测试：`apps/relay/src/modules/channels/infrastructure/adapters/wechat-clawbot/__tests__/**`（以 HTTP 桩模拟 iLink；allowedPaths 不含 tests 目录，测试置于适配器目录内）
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-041/{u02-token-quota.md,u04-latency.md,smoke.log,license-check.md}`

## 5. Execution Steps
1. [ ] 许可与来源：只读 Tencent/openclaw-weixin 的 `docs/protocol.md` 与参考项目设计，clean-room 实现，不拷贝代码；在 `license-check.md` 记录所读材料与结论（ADR-010）。
2. [ ] 扫码登录：`startQrLogin()` 调 `get_bot_qrcode?bot_type=3`，把二维码转为 `qrImageDataUrl`；`pollQrLogin()` 映射 `wait/scaned/confirmed/expired` → `waiting/scanned/confirmed/expired`（其余→failed）；确认后取得 `bot_token`、`ilink_bot_id`、`ilink_user_id`、`baseurl`，经 TASK-042 凭据服务加密保存，`bot_identity_hash = sha256(ilink_bot_id)`，唯一索引冲突→`BOT_IDENTITY_CONFLICT`。
3. [ ] 收消息：`poller.ts` 循环 `POST getupdates`（携带 `get_updates_buf`，客户端超时 ~35 s 返回空视为正常），每批处理后把新游标写 `channels.cursor`；入站以 `(channelId, 平台消息 id)` 为幂等键交给 channels 核心的 `onInbound`；`from_user_id` 映射为 recipient `platformId`（scope `direct`；协议含 `group_id` 但官方只声明私聊，群消息忽略并记日志）。
4. [ ] token 与额度：每条入站刷新该接收人的 `context_token`（加密写 `channel_tokens`，`sent_since_refresh=0`）；绝不跨接收人复用 token。
5. [ ] 发消息：`send()` 携带 `msg.to_user_id`、`msg.context_token`、`item_list[{type:1,text_item}]`；非 0 `ret` 视为失败；token 缺失/过期或额度用尽 → 不调用平台，返回 `CHANNEL_QUOTA_EXHAUSTED`；发送成功 `sent_since_refresh+1`；剩余额度 ≤3 时在本条文本末尾追加 i18n 文案“回复任意字以续期”（REQ-F-009）。
6. [ ] 健康：`ret/errcode = -14`（会话暂停 1 小时）→ health `degraded` 并暂停轮询 1 小时；鉴权失败 → health `expired` + `CHANNEL_CREDENTIAL_EXPIRED`，发 `channel.health_changed`（p0 告警由 TASK-125 处理）；网络错误指数退避。
7. [ ] 能力声明：返回 capabilities（取 channel-kinds 规划值；`quoteReply` 未经证实前为 false——iLink 引用回复字段证据不足）。
8. [ ] 单测（HTTP 桩）：扫码四态映射；游标推进与重启续读；重复平台消息只交付一次；第 11 条主动消息返回 `CHANNEL_QUOTA_EXHAUSTED`；剩余 3 条时文本含续期提示；`-14` 与鉴权失败的健康迁移；`proactiveQuota=null` 时不限额。
9. [ ] 真机验证（U-02/U-04）：真实个人微信扫码绑定；测量 token 实际有效期（入站后 23 h/25 h 各发一次）与单次入站后可成功主动发送条数；从香港中转连续 24 h 记录 getupdates/sendmessage 的 RTT 与失败率；结论写证据，如与规划值不同，提交 `channel-kinds.v1.json` 变更请求（不自行改契约）。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：适配器单测全绿（`pnpm -F @workfleet/relay test src/modules/channels/infrastructure/adapters/wechat-clawbot`）。
- [ ] AC-2：HTTP 桩：qr-login 状态按 waiting→scanned→confirmed 迁移，确认后 `channels.credential_enc` 非空、`bot_identity_hash` 写入；同一 `ilink_bot_id` 第二次绑定返回 409 `BOT_IDENTITY_CONFLICT`。
- [ ] AC-3：HTTP 桩：一次入站后第 1–10 条主动消息调用 `sendmessage`，第 8 条起（剩余 ≤3）文本含续期提示，第 11 条不调用平台并返回 `CHANNEL_QUOTA_EXHAUSTED`；新入站后额度恢复。
- [ ] AC-4：HTTP 桩：鉴权失败使 health=`expired` 并发出 `channel.health_changed`；`-14` 使 health=`degraded` 且 1 小时内不再轮询（假时钟）。
- [ ] AC-5：`EVD-041/u02-token-quota.md` 与 `u04-latency.md` 给出实测值（token 有效期、每次入站额度、RTT p50/p95、失败率、样本量、时间段），或在无真机时标 UNKNOWN 并写明 blocked 原因。
- [ ] AC-6：数据库与日志中 grep 不到明文 `bot_token`/`context_token`（REQ-NF-004）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/relay test src/modules/channels/infrastructure/adapters/wechat-clawbot
pnpm -F @workfleet/relay typecheck
# 明文凭据扫描（真机/桩运行后）
! sqlite3 $WF_RELAY_DATA_DIR/relay.db .dump | grep -E 'bot_token|context_token'
gitleaks detect --no-git --source docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-041 --no-banner
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-041/
- `u02-token-quota.md`：context_token 有效期与每次入站主动额度实测（U-02）
- `u04-latency.md`：香港中转→iLink RTT p50/p95、失败率、样本时间窗（U-04）
- `smoke.log`：真机扫码/收发日志（脱敏）
- `license-check.md`：clean-room 来源记录（ADR-010）
- `test-output.txt`

## 9. 允许修改
- `apps/relay/src/modules/channels/infrastructure/adapters/wechat-clawbot/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-041/**`

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-041/` 除外）
- `apps/relay/src/modules/channels/**` 中除 `infrastructure/adapters/wechat-clawbot/**` 外的路径（TASK-042/010）
- `apps/relay/src/modules/{delivery,routing,recipients,notifications}/**`
- `packages/testkit/**`（微信方言 FakeChannel 归 TASK-008）

## 11. 依赖与阻塞
- Depends on：TASK-042
- Blocks：TASK-048, TASK-126
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 没有已启用 ClawBot 能力的真实个人微信或香港中转 → U-02/U-04 真机项标 UNKNOWN 并 blocked（需用户提供），桩测试部分照常完成
  - 测试文件不在任何 allowedPaths 的 tests 目录 → 本卡置于适配器目录 `__tests__/` 内；若主 Agent 要求放 `apps/relay/tests/**` 需补 allowedPaths
  - 实测额度/有效期与 `channel-kinds.v1.json` 规划值不符 → 不改契约，提交变更请求（U-02 分叉点 `capabilities.proactiveQuota`）
  - 发现参考实现许可不兼容或需拷贝代码才能完成 → 停止，按 ADR-010 改为自写
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
opus　理由：微信是限制最严、不确定性最高（U-02/U-04）且涉及用户个人凭据的渠道，需要在证据不足处谨慎取舍，按 opus 执行（S2 opus 券超额问题见 cost-budget §3）。

## 13. 升级条件
- 本卡已为 opus：若实测推翻“1 微信号↔1 Bot / 不可群发”等前提，需改需求或契约 → 升 fable 并 blocked
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
大　是否小于 2 小时：否

## 15. 风险与假设
- U-02（BLOCKING，仅影响 REQ-F-009 提醒策略）：context_token 24 h 与“每次入站约 10 条”为部分确认值；默认实现方案 A（预算器 + 续期提示），实测无限制则切方案 B（`proactiveQuota=null`），适配器与路由不变。
- U-04（NON_BLOCKING）：假设香港中转可访问 iLink；本卡记录 RTT 与失败率，证据不足前不承诺 REQ-NF-001 时延。
- 风险：缺失/过期 token 发送可能被平台静默丢弃（`ret=-2`，部分确认）→ 预算器在本地先拦截，不依赖平台返回。
- 风险：腾讯可单方面限频或终止服务（部分确认）；`-14` 会话暂停 1 小时需在控制台显示 degraded。
- 风险：iLink 引用回复字段证据不足 → `quoteReply=false`，REQ-F-017 在微信上的引用溯源需真机确认后才能开启。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-041/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
