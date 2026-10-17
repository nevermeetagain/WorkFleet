# TASK-048：S2 E2E：FakeChannel(微信方言) 管理模式全链路

```yaml
id: TASK-048
slice: S2
status: todo
owner: Agent-QA
tier: sonnect
size: 中
title: "S2 E2E：FakeChannel(微信方言) 管理模式全链路"
dependsOn: ["041", "045", "046", "047"]
blocks: []
reqs: "REQ-F-009/016/017"
allowedPaths: ["tests/e2e/s2/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-048/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S2
- 来源需求：REQ-F-009、REQ-F-016、REQ-F-017（tasks.v1.json 原值 `REQ-F-009/016/017`）
- 来源方案：slices.md S2 演示脚本（控制台扫码一次；微信里 @z1/@cc1 分发，引用回复溯源，Y1 审批，额度不足提示续期）、REQ-F-009/016/017、REQ-NF-009（CI 用 FakeChannel）

## 2. 目标
Playwright + FakeChannel（微信方言）在真中转 + 真节点 + FakeAgent 下自动验证 S2 管理模式全链路：扫码绑定 → 未授权提示 → /bind 识别 → @别名分发 → /use 焦点 → 引用回复溯源 → Y1 审批 → 额度续期提示 → dry-run 预览一致。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/04_planning/slices.md S2
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-009、REQ-F-016、REQ-F-017、REQ-F-020
  - docs/WorkFleet-V0.0.2/30-协议与端点/03-输出端接入矩阵.md §1（微信 ClawBot / iLink：接口、请求头、限制与证据标签）
- 契约：
  - `packages/contracts/commands/im-commands.json`（`/bind`、`/use`、`@alias`、`Y{n}`）、`adapters/channel-kinds.v1.json`（wechat_clawbot 能力与额度）
  - `packages/contracts/api/relay.openapi.json`：`POST /api/v1/channels`、`POST /api/v1/channels/{channelId}/qr-login`、`GET /api/v1/channels/{channelId}/qr-login/{loginId}`、`POST /api/v1/recipients/bind-confirm`、`POST /api/v1/routes`、`POST /api/v1/routes/dry-run`
  - `packages/contracts/errors/error-codes.json`：`RECIPIENT_UNAUTHORIZED`、`CHANNEL_QUOTA_EXHAUSTED`；`ux/ux-states.json`（`channel_bind_wechat_qr`、`route_editor_dry_run`）
- 前置任务：TASK-041、TASK-045、TASK-046、TASK-047
- 前置状态：TASK-041、TASK-045、TASK-046、TASK-047 已合并（间接含 042/043/044）；TASK-008 FakeChannel 微信方言可作为中转适配器加载（经 TASK-042 的 `WF_RELAY_TEST_ADAPTER_MODULES`）；TASK-013 的 E2E 支撑（只读复用）

## 4. 输出
- `tests/e2e/s2/management-mode.spec.ts`（主路径）、`tests/e2e/s2/quota.spec.ts`（额度与续期提示）、`tests/e2e/s2/approval-im.spec.ts`（Y1 审批与 held）
- `tests/e2e/s2/helpers.ts`（启动中转时注入 `WF_RELAY_TEST_ADAPTER_MODULES=@workfleet/testkit/fake-channel/wechat`；FakeChannel 控制句柄：`injectInbound`、`outbox`；登记 FakeAgent 智能体 `z1`、`cc1`）

## 5. Execution Steps
1. [ ] 准备：新账号；FakeChannel 微信方言以测试适配器 kind 加载；节点登记 `z1`（夹具 basic）、`cc1`（夹具 basic）、`zp`（夹具 permission）。
2. [ ] 绑定：控制台创建微信渠道 → 扫码页出现二维码 → FakeChannel 模拟扫码确认 → 渠道健康 healthy。
3. [ ] 授权：FakeChannel 以“我”的身份发“hi” → outbox 收到固定未授权提示；发 `/bind` → 收到 6 位码 → 控制台接收人页输入 → 授权成功。
4. [ ] 路由：控制台建管理模式绑定（z1、cc1 → 我）；dry-run 输入 `@cc1 测试` 显示 target=cc1、reason=at_alias；IM 发 `@z1 你好` → 回复带 `[项目/z1]`；`/use cc1` 后发“hello”→ cc1 回复；引用 z1 的回复再回复 → 回到 z1 会话（REQ-F-017）。
5. [ ] 审批：向 `zp` 发消息 → IM 收到含 `回复 Y1` 的纯文本审批 → 期间再发 1 条进入 held → 回复 `Y1` → 智能体继续，held 消息随后处理。
6. [ ] 额度：一次入站后让智能体产生 11 条主动消息 → 第 8 条起含“回复任意字以续期”，第 11 条未送达且投递记录为可重试失败；再发任意字后积压消息送达。
7. [ ] 连续 3 次运行稳定，保存报告与 FakeChannel outbox 快照。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`pnpm e2e tests/e2e/s2` 在 ubuntu 通过，连续 3 次全部 PASS。
- [ ] AC-2：未授权发送者只收到固定提示；`/bind` + 控制台确认后消息进入路由（REQ-F-009/forbiddenPaths）。
- [ ] AC-3：`@z1`、`/use cc1`、引用回复三种方式分别路由到正确智能体，且 dry-run 预测与实际一致（REQ-F-016/017）。
- [ ] AC-4：`Y1` 批准后智能体完成 turn，held 消息按序处理（REQ-F-020）。
- [ ] AC-5：额度剩余 ≤3 条时出现续期提示；第 11 条不送达，入站后补发（REQ-F-009，U-02 方案 A 规划值）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。 E2E：`pnpm e2e <目录>`。
```bash
pnpm exec playwright install --with-deps chromium
pnpm e2e tests/e2e/s2
for i in 1 2 3; do pnpm e2e tests/e2e/s2 || exit 1; done
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-048/
- `test-output.txt`：3 次运行输出
- `playwright-report/`
- `fakechannel-outbox/`：每个用例 FakeChannel 收发快照
- `summary.md`

## 9. 允许修改
- `tests/e2e/s2/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-048/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-048/` 除外）
- `playwright.config.ts`、`tests/e2e/support/**`、`tests/e2e/{s0,s1}/**`（只读复用）
- `apps/**`、`packages/**`（发现缺陷只记录退回）

## 11. 依赖与阻塞
- Depends on：TASK-041, TASK-045, TASK-046, TASK-047
- Blocks：—
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - FakeChannel（TASK-008）与 ChannelAdapter 端口（TASK-042）签名不兼容，无法作为中转适配器加载 → blocked，需 Agent-QA 新任务做适配层
  - TASK-042 未实现 `WF_RELAY_TEST_ADAPTER_MODULES` 测试适配器注入 → blocked 提单 TASK-042
  - 额度与有效期以 U-02 规划值断言；若 TASK-041 真机结论改为方案 B（无限制），额度用例改为断言“不提示续期”并登记
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：E2E 编写属主力档，失败只记录不修产品代码，sonnect 足够。

## 13. 升级条件
- 同代码下 E2E 连续 2 次不稳定（路由/held/额度时序）→ 升 opus 跨模块排查
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- U-02（BLOCKING，仅影响提醒策略）：本卡按方案 A 规划值（24 h、每次入站 10 条）断言，真值以 TASK-041 证据为准。
- 假设（NON_BLOCKING，U-04）：E2E 不经真实 iLink，不验证跨境网络。
- 风险：微信方言引用回复在真机上未证实（TASK-041 `quoteReply=false`），本卡的引用溯源用例只证明路由内核正确，不代表微信真机可用。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-048/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
