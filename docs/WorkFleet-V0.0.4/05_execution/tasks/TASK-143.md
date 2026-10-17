# TASK-143：audit：出站/管理审计、投递明细、死信重放

```yaml
id: TASK-143
slice: S7
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Relay
tier: sonnect
size: 中
title: "audit：出站/管理审计、投递明细、死信重放"
dependsOn: ["045"]
blocks: ["145", "205"]
reqs: "REQ-F-028"
allowedPaths: ["apps/relay/src/modules/audit/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S7
- 来源需求：REQ-F-028
- 来源方案：DEC-047（每条出站记录发给谁、来自哪个输入端、经过哪些过滤）；REQ-NF-007（死信可查看与重放）；architecture §4.1 audit

## 2. 目标
提供 append-only 审计 `record()`、出站审计（每条投递可追溯接收人/来源智能体/过滤规则）、管理操作审计、`GET /api/v1/audit`、`GET /api/v1/deliveries` 与死信重放 `POST /api/v1/deliveries/{deliveryId}/replay`。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-028、REQ-NF-007）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.1、§7
  - docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md（DEC-047、DEC-049：中转只留审计所需）
- 契约：
  - packages/contracts/schemas/entities/audit-entry.schema.json（`actor.kind` user/device/system/recipient；`action` 形如 `delivery.sent`）
  - packages/contracts/schemas/entities/delivery.schema.json；schemas/common/page.schema.json
  - packages/contracts/api/relay.openapi.json：`GET /api/v1/audit`（audit.read，cursor/limit）、`GET /api/v1/deliveries`（audit.read）、`POST /api/v1/deliveries/{deliveryId}/replay`（channel.write）
  - packages/contracts/events/domain-events.json：`delivery.sent`、`delivery.failed`、`route.updated`、`approval.decided`、`emergency.stopped`、`channel.health_changed`、`device.online/offline`
  - packages/contracts/identity/permissions.json：`audit.read`（admin、viewer；operator=false）
  - database/migrations/relay/0001_init.sql：`audit_log`（触发器禁止 UPDATE/DELETE）、`deliveries`、`messages`、`conversations`
- 前置任务：TASK-045
- 前置状态：TASK-045 delivery outbox 与死信已合并；进程内事件总线（apps/relay/src/shared）可订阅。

## 4. 输出
- apps/relay/src/modules/audit/domain/、application/（record、出站审计投影、查询、重放用例）、infrastructure/（audit_log 仓储）、interfaces/http/（3 个端点）
- apps/relay/src/modules/audit/index.ts（导出 `record()`；不导出仓储）
- apps/relay/src/modules/audit/**/__tests__/
- （不含 application/twin-forward/**，那是 TASK-144 的）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-143/`（见 §8）

## 5. Execution Steps
1. [ ] 实现 `record(entry)`：校验 audit-entry schema、强制带 `traceId`、只 INSERT；验证 DB 触发器使 UPDATE/DELETE 失败。
2. [ ] 订阅 `delivery.sent`/`delivery.failed`：写 `delivery.sent`/`delivery.dead` 审计，`detail` 含 `recipientId`、`channelId`、来源 `agentId`（经 messages→conversations 关联）、`filtersApplied`、`attempts`。
3. [ ] 订阅 `route.updated`、`approval.decided`、`emergency.stopped`、`channel.health_changed`、`device.*` 写管理/系统审计；对契约事件表中没有的管理动作（成员变更、设备吊销、过滤规则变更、凭据绑定、配置导入）只提供 `record()` 供调用方使用，并在 EVD 列出缺口。
4. [ ] 实现 `GET /api/v1/audit`（按契约只支持 cursor/limit，按 created_at 倒序，严格 tenant 隔离）与 `GET /api/v1/deliveries`（含 dead）。
5. [ ] 实现重放：仅 `status=dead` 可重放，置回 `queued`、`attempts=0`、`next_attempt_at=now`，写 `delivery.replayed` 审计；非 dead → `CONFLICT`。
6. [ ] 写测试：出站一条消息后能从审计查到接收人/来源/过滤；operator 调 audit → 403；跨组织 → 404；重放幂等（同一死信重放两次第二次 409）。
7. [ ] 运行验证命令并存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 发出一条经过 2 条过滤规则的消息后，审计条目 `detail` 含接收人、来源智能体、2 个 filterRuleId（集成测试）。
- [ ] `audit_log` UPDATE/DELETE 被触发器拒绝（测试断言异常）。
- [ ] `GET /api/v1/audit`：admin/viewer 200、operator 403、他组织 404/空（测试覆盖）。
- [ ] 死信重放后状态变 `queued` 并被 outbox 工作者再次发送（FakeChannel 收到），审计含 `delivery.replayed`。
- [ ] 所有审计条目 `traceId` 非空（测试遍历断言）。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-143/
pnpm --filter ./apps/relay exec vitest run src/modules/audit --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-143/vitest.txt
pnpm --filter ./apps/relay exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-143/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-143/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-143/
- `vitest.txt`、`tsc.txt`、`guard.txt`
- `audit-gaps.md`（契约事件表缺失的管理动作清单与建议）

## 9. 允许修改
- `apps/relay/src/modules/audit/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-143/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-143/` 除外，见 ownership-matrix §4）
- apps/relay/src/modules/audit/application/twin-forward/**（TASK-144）
- apps/relay/src/modules/delivery/**、tenancy/**、devices/**（只调用公开 API/订阅事件）

## 11. 依赖与阻塞
- Depends on：TASK-045
- Blocks：TASK-145, TASK-205
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - REQ-F-028 要求“管理操作（改绑定、改权限、吊销设备）全部入审计”，但 domain-events.json 无 `device.revoked`、`member.*`、`filter.*` 事件：需各所有者模块调用 `audit.record()`，这超出本卡路径 → 在 EVD 列缺口，主 Agent 派接线任务；若验收必须覆盖则标 blocked。
  - `GET /api/v1/audit` 契约只声明 cursor/limit，summary 却写“action/resource/时间范围”：不得私加查询参数，按契约实现并报缺陷。

## 12. 建议执行档位
sonnect　理由：append-only 记录 + 查询 + 重放，表结构与触发器已冻结，逻辑直接。

## 13. 升级条件
- 需要新增领域事件或改审计 schema → opus（契约语义）。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：重放权限按契约为 `channel.write`（与查看的 `audit.read` 不同，operator 可重放但不可查看审计，记录为疑似缺陷）。
- 风险：审计量大时 `ix_audit_tenant_time` 足够分页，未做归档（v1 不做）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-143/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-143.md`）
