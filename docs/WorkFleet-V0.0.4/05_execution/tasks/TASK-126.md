# TASK-126：渠道一致性测试套件（每个适配器跑同一套用例）

```yaml
id: TASK-126
slice: S6
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-QA
tier: sonnect
size: 中
title: "渠道一致性测试套件（每个适配器跑同一套用例）"
dependsOn: ["041", "101", "123", "124", "125"]
blocks: ["210"]
reqs: "REQ-NF-008"
allowedPaths: ["tests/integration/channels/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S6（可演示：QQ/钉钉/Telegram/Discord 收发与审批；渠道断开 60 秒内 p0 告警到备用渠道）
- 来源需求：REQ-NF-008
- 来源方案：REQ-NF-008（新增 IM = 一个适配器目录 + 注册一行）、ADR-011、DEC-008（按能力降级，核心不写渠道特判）；DEC-029

## 2. 目标
编写一套参数化的渠道一致性测试，对每个已注册渠道适配器（wechat_clawbot、feishu、qq、dingtalk、telegram、discord、web）跑同一组用例，验证能力声明、幂等入站、降级渲染、审批、限流退避与健康事件行为一致。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/02_requirements/non-functional/REQ-NF-008-可扩展.md`、`REQ-NF-009-可测试.md`
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §4.1 channels（核心里不写渠道特判）
  - `docs/WorkFleet-V0.0.2/30-协议与端点/03-输出端接入矩阵.md` §9 How（能力位 + 降级）
- 契约：
  - `packages/contracts/adapters/channel-capabilities.schema.json`（14 必填位）与 `channel-kinds.v1.json`（7 个 kind）
  - `packages/contracts/schemas/entities/delivery.schema.json`（renderedAs card/markdown/text/digest）、`channel.schema.json`（health）
  - `packages/contracts/errors/error-codes.json`：CHANNEL_CAPABILITY_UNSUPPORTED、RATE_LIMITED、CHANNEL_CREDENTIAL_EXPIRED、CHANNEL_QUOTA_EXHAUSTED、APPROVAL_ALREADY_DECIDED
  - `packages/contracts/events/domain-events.json`：message.received（channelId+platformMessageId）、channel.health_changed、delivery.sent
  - `packages/contracts/commands/im-commands.json`：`/` 与 `／` 前缀、`Y{n}/N{n}`
- 前置任务：TASK-123, TASK-124, TASK-125
- 前置状态：TASK-123/124/125 已合并；各适配器目录内有 FakePlatform 夹具；channels 注册表可枚举全部适配器

## 4. 输出
- `tests/integration/channels/conformance.test.ts`：按注册表枚举适配器的参数化套件
- `tests/integration/channels/cases/`：能力、入站幂等、降级渲染、审批、限流、健康 6 组用例
- `tests/integration/channels/README.md`：新增渠道接入一致性套件的说明
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-126/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 从 channels 注册表动态枚举适配器（不硬编码列表），断言 kind 集合 ⊇ channel-kinds.v1.json 中的 7 个 kind，缺失的渠道记为 SKIP 并在证据中列明原因。
2. [ ] 能力用例：每个适配器声明的 capabilities 通过 channel-capabilities.schema.json 校验。
3. [ ] 入站幂等用例：同一平台消息投递两次只产生 1 条 message.received；全角 `／help` 与半角 `/help` 被同样识别。
4. [ ] 降级渲染用例：同一 IR（含卡片与按钮）在 cards=false/buttons=false 的渠道降级为 markdown/text 且审批以 `Y{n}/N{n}` 呈现；不支持的能力不导致发送失败。
5. [ ] 审批用例：按钮或口令批准后状态一致；重复决策返回 APPROVAL_ALREADY_DECIDED。
6. [ ] 限流与健康用例：Fake 平台返回限流 → SendReceipt 带 retryAfter 且不丢消息；凭据失效 → health=expired 并发出 channel.health_changed。
7. [ ] “核心零改动”检查：在证据中记录新增一个 Fake 渠道只需新增适配器目录 + 注册一行即可通过套件（以 testkit FakeChannel 演示）。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 套件对注册表中每个适配器执行同一组 6 类用例，结果矩阵（渠道 × 用例）写入证据
- [ ] 7 个 kind 全部 PASS 或带原因 SKIP；非 SKIP 渠道无 FAIL
- [ ] 新增 Fake 渠道无需修改 channels 核心即通过套件（REQ-NF-008）
- [ ] 越界检查只输出 SCOPE OK

## 7. 验证命令
```bash
pnpm exec vitest run tests/integration/channels --reporter=verbose | tee /tmp/channels-conformance.txt
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(tests/integration/channels/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-126/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-126/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `tests/integration/channels/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-126/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/**（发现缺陷提给对应适配器任务）
- packages/testkit/**

## 11. 依赖与阻塞
- Depends on：TASK-041, TASK-101, TASK-123, TASK-124, TASK-125
- Blocks：TASK-210
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - TASK-101（飞书）与 TASK-041（微信）不在本任务依赖链上：若执行时尚未合并，对应 kind 记 SKIP，不得伪造通过
  - channels 注册表不支持枚举，必须硬编码适配器列表才能测试 → 停止并请求 TASK-042 所有者
  - 某适配器未提供 FakePlatform 夹具，无法在 CI 中运行

## 12. 建议执行档位
sonnect　理由：参数化测试编写，判定标准来自契约 schema。

## 13. 升级条件
- 一致性失败揭示核心存在渠道特判 → 升 opus 审查 TASK-042/045
- 需要定义新的跨渠道语义（如编辑消息一致性）→ 升 opus

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- 无 U-xx 直接关联；R-06（QQ 配额文档冲突）不影响本套件，因只测能力声明与降级行为。
- channel-kinds.v1.json 各行缺 schema 必填位，套件以适配器运行时声明为准，不校验该文件本身。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - 规划：126 未依赖 TASK-101 与 TASK-041，飞书与微信可能在套件执行时缺席
  - Agent-Contract：channel-kinds.v1.json 各行不满足 channel-capabilities.schema.json 的必填位

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-126/
- 验证者结论：
- 遗留问题 / 跟进项编号：
