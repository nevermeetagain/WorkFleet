# TASK-046：Web：渠道页（扫码 UI）、接收人页、绑定编辑器 + dry-run

```yaml
id: TASK-046
slice: S2
status: todo
owner: Agent-App
tier: sonnect
size: 大
title: "Web：渠道页（扫码 UI）、接收人页、绑定编辑器 + dry-run"
dependsOn: ["027", "044"]
blocks: ["048", "065"]
reqs: "REQ-F-009/016"
allowedPaths: ["apps/web/src/pages/channels/**", "apps/web/src/features/channels/**", "apps/web/src/pages/routes/**", "apps/web/src/features/routes/**", "apps/web/src/features/recipients/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-046/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S2
- 来源需求：REQ-F-009、REQ-F-016（tasks.v1.json 原值 `REQ-F-009/016`）
- 来源方案：REQ-F-009（控制台扫码一次完成绑定）、REQ-F-016（三种绑定可在控制台创建并有 dry-run 预览）、REQ-NF-005（控制台明示“中转可见 IM 明文”）、ADR-008（rjsf 按 configSchema）、ux-states.json

## 2. 目标
Web 增加渠道页（含微信扫码绑定 UI 与健康状态）、接收人页（授权、/bind 确认、静默时段）、绑定编辑器（管理模式）与 dry-run 面板；六个界面实现 UX 6 态。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-009、REQ-F-016、REQ-NF-005
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-008-前端.md
  - docs/项目完整目录结构.txt §10.2
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`GET/POST /api/v1/channels`、`DELETE /api/v1/channels/{channelId}`、`GET /api/v1/adapters/channel`、`POST /api/v1/channels/{channelId}/credential`、`POST /api/v1/channels/{channelId}/qr-login`、`GET /api/v1/channels/{channelId}/qr-login/{loginId}`、`POST /api/v1/channels/{channelId}/test`、`GET /api/v1/recipients`、`POST /api/v1/recipients/{recipientId}/authorize`、`POST /api/v1/recipients/bind-confirm`、`PATCH /api/v1/recipients/{recipientId}`、`GET/POST /api/v1/routes`、`PATCH/DELETE /api/v1/routes/{routeId}`、`POST /api/v1/routes/dry-run`
  - `packages/contracts/schemas/entities/{channel,recipient,route}.schema.json`、`adapters/channel-capabilities.schema.json`（能力徽标）
  - `packages/contracts/ux/ux-states.json` screens `channel_list`、`channel_bind_wechat_qr`、`channel_form`、`recipient_list`、`route_list`、`route_editor_dry_run`
  - `packages/contracts/errors/error-codes.json`：`BOT_IDENTITY_CONFLICT`（向导阻断 + 说明）、`CHANNEL_CREDENTIAL_EXPIRED`（渠道卡片红点 + 重新扫码）、`ROUTE_INVALID`（dry-run 面板显示原因）、`NOT_FOUND`（bind-confirm 码错误）
- 前置任务：TASK-027、TASK-044
- 前置状态：TASK-027（Web 智能体页、rjsf 已接入）与 TASK-044（routes/dry-run API）已合并；TASK-042/043 的渠道与接收人 API 可用

## 4. 输出
- `apps/web/src/pages/channels/{routes.tsx,ChannelListPage.tsx,ChannelFormPage.tsx}`、`apps/web/src/features/channels/**`（`WechatQrBind`：显示二维码、每 2 s 轮询状态、过期一键刷新；健康徽标；测试发送；隐私提示条“中转可见 IM 明文”）
- `apps/web/src/features/recipients/**`（接收人列表、授权开关、6 位码确认框、静默时段编辑；挂在渠道页的“接收人”标签下）
- `apps/web/src/pages/routes/{routes.tsx,RouteListPage.tsx,RouteEditorPage.tsx}`、`apps/web/src/features/routes/**`（管理模式绑定编辑：来源智能体多选、目标接收人、默认来源、优先级下限；`DryRunPanel`）
- 同目录测试 `*.test.tsx`

## 5. Execution Steps
1. [ ] 渠道列表/表单：`GET /adapters/channel` 取渠道类型与 configSchema（rjsf 渲染）；创建后若渠道支持扫码（微信）进入 `WechatQrBind`，否则进入凭据表单（`POST /credential`，提交后清空输入，不回显）。
2. [ ] `WechatQrBind`：`POST /qr-login` 显示 `qrImageDataUrl` 与倒计时；每 2 s `GET /qr-login/{loginId}`，waiting→scanned→confirmed 显示对应文案；expired 显示刷新按钮；`BOT_IDENTITY_CONFLICT` 阻断并说明“该 Bot 已被其他程序/账号使用（一个 Bot 身份只允许一个消费者）”。
3. [ ] 健康：`health=expired` 显示红点与“重新扫码”；页面顶部固定隐私提示（REQ-NF-005）。
4. [ ] 接收人：列表显示平台名、类型、授权状态、关联用户；授权开关（`recipient.authorize`）；“输入 6 位码”框调用 `bind-confirm`，`NOT_FOUND` 显示“验证码错误或已过期”；静默时段编辑。
5. [ ] 绑定编辑器：选择模式（本卡仅 management 可选，其余置灰提示“即将支持”）、来源智能体、目标接收人、默认来源；保存时 `ROUTE_INVALID` 显示 `details`；`DryRunPanel` 输入样例文本/引用消息 id → 显示 `targetAgentId`、`reason`、`held`、`outboundPreview`。
6. [ ] 六个 screen 的 6 态与 `data-ux-state`；文案进 i18n 命名空间。
7. [ ] 测试：扫码轮询状态迁移与过期刷新；凭据提交后输入清空；bind-confirm 错误；dry-run 结果渲染；`ROUTE_INVALID` 展示；各屏 6 态。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`pnpm -F @workfleet/web test src/features/channels src/features/recipients src/features/routes` 全绿。
- [ ] AC-2：`WechatQrBind` 组件测试：模拟轮询返回 waiting→scanned→confirmed，界面依次切换且停止轮询；expired 时出现刷新按钮。
- [ ] AC-3：凭据表单提交 204 后输入框清空、页面无 secret 文本残留；`BOT_IDENTITY_CONFLICT` 时显示阻断说明。
- [ ] AC-4：DryRunPanel 渲染 `reason`（如 at_alias）与 `outboundPreview`；保存返回 422 `ROUTE_INVALID` 时显示原因。
- [ ] AC-5：六个 screen 各 6 态有测试并断言 `data-ux-state`；渠道页存在“中转可见 IM 明文”提示（REQ-NF-005）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/web test src/features/channels src/features/recipients src/features/routes
pnpm -F @workfleet/web typecheck && pnpm -F @workfleet/web build
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-046/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/web/src/pages/channels/**`
- `apps/web/src/features/channels/**`
- `apps/web/src/pages/routes/**`
- `apps/web/src/features/routes/**`
- `apps/web/src/features/recipients/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-046/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-046/` 除外）
- `apps/web/src/features/routes/modes/**`（TASK-104）
- `apps/web/src/{app,components,data-access,lib,styles,i18n}/**`（TASK-009）
- `apps/web/src/features/{agents,chat,approvals}/**`
- `apps/relay/**`、`apps/node/**`

## 11. 依赖与阻塞
- Depends on：TASK-027, TASK-044
- Blocks：TASK-048, TASK-065
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - `GET /api/v1/adapters/channel` 响应项为无类型 object（契约未定义 configSchema/默认能力字段名）→ 按 TASK-042 实现的字段渲染并登记；字段不一致时 blocked
  - 接收人页无独立 pages 路由（allowedPaths 只有 `features/recipients/**`）→ 挂在渠道页内；若需独立路由需补 allowedPaths
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：控制台表单与轮询 UI 属主力档前端工作，sonnect 足够。

## 13. 升级条件
- 扫码流程在真机（TASK-041 证据）与 UI 状态映射不一致需改契约状态枚举 → 升 opus 并 blocked
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
大　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-02）：额度/续期提示在 IM 侧呈现，控制台仅展示渠道健康；剩余额度展示需契约字段（当前无）。
- 假设：微信需用户先在微信内启用 ClawBot 能力（部分确认），页面给出前置说明。
- 风险：通知/团队模式编辑（REQ-F-016 其余部分）在 TASK-104，本卡只完成管理模式。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-046/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
