# TASK-144：twin：采集（twin.capture）、节点存储、本机查看/修改/删除/导出

```yaml
id: TASK-144
slice: S7
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Node
tier: sonnect
size: 中
title: "twin：采集（twin.capture）、节点存储、本机查看/修改/删除/导出"
dependsOn: ["063"]
blocks: ["145"]
reqs: "REQ-F-029"
allowedPaths: ["apps/node/src/modules/twin/**", "apps/relay/src/modules/audit/application/twin-forward/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S7
- 来源需求：REQ-F-029
- 来源方案：DEC-049（分身数据范围、只存节点）；architecture §4.2 twin、§7 数据归属；REQ-NF-005

## 2. 目标
用户本人发出的全部指令（IM/Web 消息、审批、纠正、/命令）与任务时间线写入节点 `twin_events`；中转经 `twin.capture` 帧把中转侧原始事件转发给该用户的主设备；本机 API 可查看/修改/删除/导出 JSONL。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-029、REQ-NF-005）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.2、§7
  - docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md（DEC-049）
- 契约：
  - packages/contracts/protocol/frames/twin.capture.schema.json（方向 relay→node，`event` 引用 twin-event）；protocol/envelope.schema.json（seq/ack、idempotencyKey）
  - packages/contracts/schemas/entities/twin-event.schema.json（kind：instruction/approval/correction/command/task_started/task_finished/routed/decision_point）
  - packages/contracts/api/node-local.openapi.json：`GET /local/v1/twin/events`、`PATCH/DELETE /local/v1/twin/events/{twinEventId}`、`GET /local/v1/twin/export`
  - packages/contracts/events/domain-events.json：`message.received`、`message.routed`、`approval.decided`（中转侧触发源）
  - database/migrations/node/0001_init.sql：`twin_events`（`edited_at`、`deleted_at`）；relay：`devices.is_primary`、`recipients.linked_user_id`、`node_outbox`
- 前置任务：TASK-063
- 前置状态：TASK-063 多中转 relay-link 已合并（帧按 relay link 命名空间分发）；TASK-062 主设备已合并。

## 4. 输出
- apps/node/src/modules/twin/（domain、application：capture/list/edit/delete/export、infrastructure：twin_events 仓储、interfaces：本机 4 个端点 + `twin.capture` 帧处理器）
- apps/node/src/modules/twin/index.ts
- apps/relay/src/modules/audit/application/twin-forward/（订阅中转事件 → 判定“用户本人” → 生成 twin-event → `node-gateway.sendToNode(primaryDevice, twin.capture)`）
- 两侧 `__tests__/`
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-144/`（见 §8）

## 5. Execution Steps
1. [ ] relay twin-forward：订阅 `message.received`（作者为 Web 登录用户本人，或 IM 接收人 `linked_user_id` 为该用户）、`approval.decided`（decidedBy 为用户）与指令执行，映射为 instruction/command/approval/correction 事件；只转发给该用户在本组织的主设备，离线则进 `node_outbox` 排队。
2. [ ] relay 侧只保留审计所需：不在 relay.db 新增任何分身存储（只调用 audit.record 记录“已转发”元数据，不含正文）。
3. [ ] node twin：注册 `twin.capture` 帧处理器（按 `event.id` 幂等 INSERT），并订阅节点内会话事件生成 task_started/task_finished（含 durationMs）、routed、decision_point。
4. [ ] node twin：实现 list（按 created_at 倒序，过滤 deleted_at）、PATCH（只改 `text`，置 `editedAt`）、DELETE、export（每行一条 twin-event JSON，逐行可被 schema 校验）。
5. [ ] 删除语义：DELETE 物理删除该行（隐私优先，REQ-NF-005）；`deleted_at` 列不用，记入 EVD 待裁决。
6. [ ] 写测试：relay 侧 Web 消息/IM 已绑定用户消息/审批 → 节点收到 twin.capture；他人（未绑定接收人）的消息不转发；重复帧不重复入库；export 每行通过 ajv 校验。
7. [ ] 运行验证命令并存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 用户本人在 Web 与已绑定 IM 发出的消息、/命令、审批各生成一条 twin_event 到主设备节点（集成测试 FakeRelay/FakeChannel）。
- [ ] 非本人（他人或未绑定接收人）的消息不产生 twin_event（测试断言）。
- [ ] 同一 `twin.capture` 帧重放两次只入库一次。
- [ ] `GET /local/v1/twin/export` 每行通过 twin-event.schema.json 校验；PATCH 后 `editedAt` 非空；DELETE 后 list/export 均不含该条。
- [ ] relay.db 中不存在 twin 正文（测试在 relay 库 grep 测试指令文本 0 命中，审计记录除外仅含 id）。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-144/
pnpm --filter ./apps/node exec vitest run src/modules/twin --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-144/node-vitest.txt
pnpm --filter ./apps/relay exec vitest run src/modules/audit/application/twin-forward --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-144/relay-vitest.txt
pnpm -r exec tsc --noEmit | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-144/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-144/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-144/
- `node-vitest.txt`、`relay-vitest.txt`、`tsc.txt`、`guard.txt`
- `sample-export.jsonl`（用测试数据生成，不含真实用户数据）
- `delete-semantics.md`

## 9. 允许修改
- `apps/node/src/modules/twin/**`
- `apps/relay/src/modules/audit/application/twin-forward/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-144/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-144/` 除外，见 ownership-matrix §4）
- apps/relay/src/modules/audit/ 下除 application/twin-forward 外文件（TASK-143）
- apps/node/src/modules/relay-link/**、sessions/**（只用公开 API/事件）
- apps/node/src/modules/local-console/**

## 11. 依赖与阻塞
- Depends on：TASK-063
- Blocks：TASK-145
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 节点帧分发（relay-link）与本机 API 路由注册（local-console）不在允许路径：若 TASK-063/066 未提供按模块注册处理器/路由的机制 → blocked。
  - 节点内无“任务开始/结束”领域事件（domain-events.json 节点侧仅 budget/supervisor/meeting/lease）：若 agents/sessions 未发出可订阅事件，时间线部分 blocked 并报缺陷。

## 12. 建议执行档位
sonnect　理由：schema 与表已冻结，采集映射与 CRUD 直接；隐私边界由验收用例锁定。

## 13. 升级条件
- 需要改变“谁算用户本人”的判定或让中转存分身正文 → opus（隐私语义，DEC-049）。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否　两侧各半天。

## 15. 风险与假设
- 契约疑点：`twin/events` 返回裸数组无分页，`twin/export` 声明为 application/json 字符串而非 NDJSON（报缺陷，按契约实现）。
- 假设：只转发给主设备（推断）；无主设备时转发给该用户最近在线设备。
- 假设：本机控制台中的操作同样是“用户本人”指令（推断）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-144/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-144.md`）
