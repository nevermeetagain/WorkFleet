# TASK-043：recipients：授权、/bind 识别我的账号、未授权固定提示

```yaml
id: TASK-043
slice: S2
status: todo
owner: Agent-Relay
tier: sonnect
size: 中
title: "recipients：授权、/bind 识别我的账号、未授权固定提示"
dependsOn: ["042"]
blocks: ["044"]
reqs: "REQ-F-009/018"
allowedPaths: ["apps/relay/src/modules/recipients/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-043/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S2
- 来源需求：REQ-F-009、REQ-F-018（tasks.v1.json 原值 `REQ-F-009/018`）
- 来源方案：DEC-030（IM 发送者默认未授权）、REQ-NF-004、architecture §6.1 第 2 步（未授权只回固定提示，不入路由）、glossary（识别我的账号 /bind）、im-commands.json（未授权发送者只能使用 /bind）

## 2. 目标
中转识别并登记每个 IM 接收人，默认未授权；未授权发送者只收到固定提示且只能用 `/bind`；`/bind` 生成 6 位码，用户在控制台确认后接收人关联到其账号并授权。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.1（recipients）、§6.1
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-009、REQ-F-018、REQ-NF-004、§8（识别我的账号为隐含前置）
  - docs/WorkFleet-V0.0.4/00_governance/glossary.md（接收人、识别我的账号）
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/recipients`（recipient.read）、`POST /api/v1/recipients/{recipientId}/authorize`（`{authorized, linkedUserId?}`，recipient.authorize）、`POST /api/v1/recipients/bind-confirm`（`{code:^[0-9]{6}$}`；`NOT_FOUND`）、`PATCH /api/v1/recipients/{recipientId}`（静默时段）
  - `packages/contracts/schemas/entities/recipient.schema.json`（platformId、scope direct|group|channel、displayName、linkedUserId、authorized、quietHours{start,end,tz}）
  - `packages/contracts/commands/im-commands.json`（`/bind`：“在 IM 内发起识别我的账号，返回 6 位码到控制台确认”）、`identity/permissions.json` forbiddenPaths（未授权发送者不得触发路由）
  - `packages/contracts/errors/error-codes.json`：`RECIPIENT_UNAUTHORIZED`（403，IM 内固定提示）、`NOT_FOUND`
  - 表：`recipients`（`ux_recipients_platform(channel_id, platform_id, scope)`、`authorized`、`linked_user_id`、`bind_code`、`bind_code_expires_at`、`quiet_hours`、version）
- 前置任务：TASK-042
- 前置状态：TASK-042 已合并（`channels.onInbound` 扩展点、`channels.send`）；TASK-024 的 `registerCommand` 可用

## 4. 输出
- `apps/relay/src/modules/recipients/{domain,application,interfaces/http,infrastructure}/**`、`index.ts`（公开 `resolveRecipient(channelId, platformId, scope, displayName)`、`gateInbound(event) → {allowed, recipient}`、`linkedPrincipal(recipient)`）
- `/bind` 执行器：在本模块 `register()` 中经 `commands.registerCommand('bind', …)` 注册
- 测试：`apps/relay/tests/unit/modules/recipients/**`、`apps/relay/tests/integration/modules/recipients/**`

## 5. Execution Steps
1. [ ] `resolveRecipient`：按 `(channel_id, platform_id, scope)` upsert，新建时 `authorized=0`、`linked_user_id=null`，displayName 随入站更新。
2. [ ] `gateInbound`：订阅 `channels.onInbound`（先于 routing）；未授权且文本不是 `/bind`（含全角 `／bind`）→ 经 `channels.send` 回固定提示（i18n：“你尚未被授权。请发送 /bind 并在 WorkFleet 控制台输入验证码。”），不进入路由；固定提示对同一接收人 10 分钟内最多发一次（防刷屏/防额度消耗）。
3. [ ] `/bind`：生成 6 位数字码（在本组织未过期码中唯一），写 `bind_code` 与 10 分钟过期；回发“验证码 123456，10 分钟内在控制台『接收人』页输入”。
4. [ ] `POST /bind-confirm`：按 code 查本组织未过期记录，不存在/过期→404 `NOT_FOUND`；成功→`linked_user_id=principal.userId`、`authorized=1`、清除 code；返回 Recipient。
5. [ ] `POST /{id}/authorize`：admin/operator 直接授权/取消授权并可指定 linkedUserId（须为本组织成员，否则 404）；`PATCH`：quietHours 校验格式。
6. [ ] `linkedPrincipal`：授权接收人的后续指令以其 linkedUser 在该组织的角色执行权限判定（供 TASK-044/047）；未关联用户的已授权接收人按 operator 以下最小权限（只可 `agent.prompt`）——本卡假设，已登记。
7. [ ] 测试：新接收人未授权收到固定提示且路由未被调用；/bind→确认→授权全流程；过期码 404；跨组织 code 不可用；固定提示限频。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：集成测试（测试替身渠道）：新发送者发“hello”→收到固定提示，routing 订阅者未被调用（forbiddenPaths：未授权不得触发路由）。
- [ ] AC-2：发送 `/bind` → 收到 6 位码；控制台 `POST /recipients/bind-confirm{code}` → 200，recipient `authorized=true`、`linkedUserId=当前用户`；之后“hello”进入路由。
- [ ] AC-3：过期或他组织的码 → 404 `NOT_FOUND`；`code` 非 6 位数字 → 400 `VALIDATION_FAILED`。
- [ ] AC-4：viewer 调 `POST /recipients/{id}/authorize` → 403 `FORBIDDEN`。
- [ ] AC-5：同一未授权接收人 10 分钟内连发 5 条只收到 1 次固定提示。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/relay test tests/unit/modules/recipients tests/integration/modules/recipients
pnpm -F @workfleet/relay typecheck
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-043/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/relay/src/modules/recipients/**`
- 明确写出的测试目录（本模块专属；allowedPaths 未含测试路径，按任务指令 §3 在此显式声明，执行前须经主 Agent 确认）：
  - `apps/relay/tests/unit/modules/recipients/**`
  - `apps/relay/tests/integration/modules/recipients/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-043/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-043/` 除外）
- `apps/relay/src/modules/{channels,commands,routing,conversations}/**`（仅经其 index 公开 API/扩展点交互）
- `apps/web/**`

## 11. 依赖与阻塞
- Depends on：TASK-042
- Blocks：TASK-044
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - TASK-042 的 `onInbound` 订阅不支持顺序/拦截（gate 需先于 routing 且能阻止传播）→ blocked 提单 TASK-042
  - im-commands.json 中 `/bind` 的 permission 为 `recipient.authorize`，但未授权发送者没有 principal → 本卡对 `/bind` 豁免权限判定（符合该文件 $comment“未授权发送者只能使用 /bind”），冲突已登记
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：授权闸门逻辑清晰、表结构已定，sonnect 足够；安全语义来自契约 forbiddenPaths。

## 13. 升级条件
- “已授权但未关联用户”的权限模型需正式定义（影响 RBAC）→ 升 opus 评审
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：已授权未关联接收人的最小权限为本卡假设（契约未定义）。
- 假设（NON_BLOCKING，U-02）：微信渠道固定提示也消耗主动额度，故限频 10 分钟一次。
- 风险：`bind_code` 无唯一索引，并发生成可能撞码 → 应用层重试 + 组织内校验。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-043/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
