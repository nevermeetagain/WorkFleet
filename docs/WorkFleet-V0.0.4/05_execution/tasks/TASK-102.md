# TASK-102：routing：通知模式（按发送人分会话）、团队模式（只到一个目标）、模式约束校验

```yaml
id: TASK-102
slice: S5
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Relay
tier: opus
size: 中
title: "routing：通知模式（按发送人分会话）、团队模式（只到一个目标）、模式约束校验"
dependsOn: ["044"]
blocks: ["103", "142"]
reqs: "REQ-F-016/017"
allowedPaths: ["apps/relay/src/modules/routing/application/modes/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S5（可演示：场景 2——三个来源汇总后分别发给老板与数据部；通知模式两人回话分会话）
- 来源需求：REQ-F-016/017
- 来源方案：ADR-006；DEC-005（不由 LLM 选渠道）、DEC-006（团队模式不广播）、DEC-046（微信不群发）、G25（按发送人分会话）；architecture §4.1 routing、§6.3

## 2. 目标
在 routing 内核上实现通知模式（一源多收，接收人回话按 (route, recipient) 分独立会话）、团队模式（多对多，但每条入站只到一个目标）与绑定创建/修改时的模式约束校验（不满足返回 ROUTE_INVALID，dry-run 同口径）。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §4.1 routing（确定性选路、按发送人分会话、dry-run；MUST NOT 让 LLM 选渠道）、§6.3
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-016-绑定与三种模式.md`、`REQ-F-017-回复溯源与按发送人分会话.md`
  - `docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md` §5 MUST NOT 2/3/4、§6 冲突 #2
  - `docs/WorkFleet-V0.0.2/30-协议与端点/03-输出端接入矩阵.md` §0 硬约束 1（微信不能做通知/群发，部分确认）
- 契约：
  - `packages/contracts/schemas/entities/route.schema.json`（mode management/notification/team/supervisor、sources≥1、targets≥1、defaultSourceId、priorityFloor）
  - `packages/contracts/api/relay.openapi.json`：`POST /api/v1/routes`（x-errors ROUTE_INVALID）、`PATCH /api/v1/routes/{routeId}`、`POST /api/v1/routes/dry-run`
  - `packages/contracts/errors/error-codes.json`：ROUTE_INVALID（422，ui“dry-run 面板显示原因”）
  - `packages/contracts/events/domain-events.json`：message.routed、route.updated
  - `packages/contracts/adapters/channel-kinds.v1.json`：wechat_clawbot notes“个人授权，不群发”；`broadcastChannel` 能力位
  - `database/migrations/relay/0001_init.sql`：`routes`/`route_sources`/`route_targets`、`recipient_focus`、`conversations`（`ux_conversations_active` = (agent_id, route_id, recipient_id) 唯一 active）、`recipients.linked_user_id`
- 前置任务：TASK-044
- 前置状态：TASK-044 routing 内核（管理模式、/use 焦点、@别名、引用回复溯源、dry-run）已合并并暴露模式扩展点

## 4. 输出
- `apps/relay/src/modules/routing/application/modes/notification/`：出站扇出到全部 targets；入站按 (route, recipient) 取/建会话
- `apps/relay/src/modules/routing/application/modes/team/`：入站单目标选择（引用回复 > @别名 > 焦点 > defaultSourceId），绝不广播
- `apps/relay/src/modules/routing/application/modes/constraints/`：模式约束校验器（供 routes 写入与 dry-run 共用）
- `apps/relay/src/modules/routing/application/modes/__tests__/`
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-102/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 把模式约束写成表驱动规则并在证据中列出：management = 多源→1 目标；notification = 1 源→多目标；team = 多源↔多目标；supervisor 仅校验结构（行为属 S8）。
2. [ ] 实现约束：notification 的 targets 不得包含“非本人”的 wechat_clawbot 接收人（recipient.linked_user_id ≠ 绑定创建者 → ROUTE_INVALID，DEC-046）；scope=channel 的目标要求渠道 broadcastChannel=true。
3. [ ] 实现 team 约束：必须存在确定的入站单目标规则（defaultSourceId 非空，或在 details 中提示“入站需显式 @别名”），否则 ROUTE_INVALID（具体口径由本卡 opus 执行者确认并写入证据）。
4. [ ] 实现 notification 入站：接收人回话 → 查 conversations(agent=唯一源, route, recipient) active 会话，不存在则新建；两个接收人永远不共享会话（G25）。
5. [ ] 实现 team 入站：按 引用回复溯源 > `@别名` > recipient_focus > defaultSourceId 的优先级选出恰好 1 个目标；无法确定时回固定提示，不广播（DEC-006）。
6. [ ] 接入 dry-run：同一约束校验器与选路函数输出“会去哪里”的解释，不产生副作用。
7. [ ] 写表驱动单测：三种模式各合法/非法样例、微信群发拒绝、两接收人两会话、团队模式 1000 次随机入站均只到 1 个目标。
8. [ ] 跑 `make guard`，确认不依赖任何模型调用模块。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] `POST /routes` 创建 notification 绑定且目标含他人微信接收人 → 422 ROUTE_INVALID；dry-run 返回同一原因
- [ ] 通知模式两个接收人各回一句，产生 2 个不同 conversationId（单测断言 ux_conversations_active 语义）
- [ ] 团队模式随机 1000 次入站，每次 message.routed 的目标数恰为 1
- [ ] 三种模式的合法/非法样例表全部通过，样例表写入证据
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过

## 7. 验证命令
```bash
pnpm --filter @workfleet/relay exec vitest run src/modules/routing/application/modes
pnpm --filter @workfleet/relay exec tsc --noEmit
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/relay/src/modules/routing/application/modes/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-102/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-102/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `apps/relay/src/modules/routing/application/modes/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-102/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/relay/src/modules/routing/** 中 application/modes/ 以外的部分（TASK-044 / 062 所有）
- apps/relay/src/modules/orchestration/**（TASK-103）
- apps/relay/src/modules/permissions-filter/**（TASK-142）

## 11. 依赖与阻塞
- Depends on：TASK-044
- Blocks：TASK-103, TASK-142
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - TASK-044 未暴露模式扩展点，必须修改内核文件才能接入 → 停止并请求规划（不得越界改 routing 其他目录）
  - 判定“他人微信”需要的数据（绑定创建者/接收人归属）在 routes 表中不存在（routes 无 created_by 字段）→ 用请求方 principal 判定，若仍不足则 blocked
  - team 模式无确定目标时的产品口径（拒绝 vs 提示）需用户确认

## 12. 建议执行档位
opus　理由：模式语义是路由核心规则，错误会导致误投或群发违规（MUST NOT），需要 opus 判断。

## 13. 升级条件
- 需要修改 route.schema 或新增错误码 → 升 fable（冻结契约变更）
- 与 TASK-142 过滤顺序冲突 → opus 仲裁（同档内）

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- 接入矩阵 §0（部分确认）：微信 ClawBot 1:1 绑定 + 24h token，不能做通知/群发——本任务以约束校验落实。
- U-02（BLOCKING，仅影响 REQ-F-009 提醒策略）：与本任务无直接关系，但通知模式不得依赖微信额度。
- 假设：supervisor 模式行为在 S8 实现，本任务只做结构校验（推断）。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - Agent-Contract/Agent-Data：routes 表与 route.schema 无创建者字段，“他人微信”判定依赖调用方身份
  - Agent-Contract：route.schema 未表达各模式的基数约束（仅 minItems:1），约束只存在于实现中

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-102/
- 验证者结论：
- 遗留问题 / 跟进项编号：
