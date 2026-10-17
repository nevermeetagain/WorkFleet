# TASK-201：急停（中转）：/stop all、EMERGENCY_STOPPED、恢复

```yaml
id: TASK-201
slice: S10
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Relay
tier: sonnect
size: 小
title: "急停（中转）：/stop all、EMERGENCY_STOPPED、恢复"
dependsOn: ["045"]
blocks: ["202"]
reqs: "REQ-F-033"
allowedPaths: ["apps/relay/src/modules/system/application/emergency/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S10
- 来源需求：REQ-F-033
- 来源方案：G9 急停；REQ-F-033；commands/im-commands.json `/stop all`；architecture §4.1 system

## 2. 目标
中转侧实现急停：`/stop all`（IM/Web）或 `POST /api/v1/emergency/stop-all` 后立即标记组织为急停、向该组织所有设备下发 `emergency.stop` 帧、冻结出站与新入站执行（返回 `EMERGENCY_STOPPED` 423），并支持 `POST /api/v1/emergency/resume` 恢复；从请求到所有在线节点确认 ≤5 秒。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-033）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.1
  - docs/WorkFleet-V0.0.4/00_governance/glossary.md（急停）
- 契约：
  - packages/contracts/api/relay.openapi.json：`POST /api/v1/emergency/stop-all`（emergency.stop_all，body `reason`，202）、`POST /api/v1/emergency/resume`（emergency.resume，仅 admin，202）
  - packages/contracts/protocol/frames/emergency.stop.schema.json（`reason`）、emergency.resume.schema.json、ack.schema.json
  - packages/contracts/events/domain-events.json：`emergency.stopped`（幂等键 tenantId+at）；errors/error-codes.json：`EMERGENCY_STOPPED`（423）
  - packages/contracts/commands/im-commands.json：`/stop all`（emergency.stop_all）；ux/ux-states.json：screen `emergency_banner`
  - database/migrations/relay/0001_init.sql：`tenants.emergency_stopped_at`、`node_outbox`、`deliveries`
- 前置任务：TASK-045
- 前置状态：TASK-045 delivery outbox 已合并；TASK-006 node-gateway `sendToNode` 可用。

## 4. 输出
- apps/relay/src/modules/system/application/emergency/（stopAll、resume、isStopped(tenantId) 查询、出站/入站闸门函数）
- apps/relay/src/modules/system/application/emergency/__tests__/
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-201/`（见 §8）

## 5. Execution Steps
1. [ ] 实现 `stopAll(principal, reason)`：校验权限 → 写 `tenants.emergency_stopped_at` → 发 `emergency.stopped` → 对组织内所有未吊销设备 `sendToNode(emergency.stop)`（离线设备进 outbox，上线即收到）→ 写审计。
2. [ ] 实现闸门：导出 `isStopped(tenantId)` 与 `assertNotStopped()`（抛 `EMERGENCY_STOPPED`），供 routing（入站执行前）与 delivery（出站发送前）调用；急停期间出站保持 queued 不发送（冻结而非丢弃），急停本身的 Web 横幅/stream 事件除外。
3. [ ] 实现 `resume(principal)`：仅 admin（permissions.json）→ 清除 `emergency_stopped_at` → 下发 `emergency.resume` → outbox 恢复发送 → 审计。
4. [ ] 计时：记录每台在线设备对 emergency.stop 帧的 ack 时间，暴露“生效耗时”指标（/metrics 或日志）。
5. [ ] 写测试：FakeRelay/FakeNode 两台在线设备 + 1 台离线；stop 后 5 s 内两台 ack、出站 0 发送、新 prompt 返回 423；resume 后排队的出站被发送；operator 调 resume → 403；重复 stop 幂等。
6. [ ] 运行验证命令并存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] stop-all 后所有在线设备在 5 s 内 ack `emergency.stop`（测试中断言实测耗时并写入证据）。
- [ ] 急停期间 FakeChannel 收到的外发数为 0，排队消息在 resume 后全部发出且不重复。
- [ ] 急停期间对智能体的新指令返回 423 `EMERGENCY_STOPPED`。
- [ ] resume 仅 admin 可调用（operator/viewer 403）；stop-all viewer 403。
- [ ] 离线设备上线后立即收到 emergency.stop（outbox 续传测试）。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-201/
pnpm --filter ./apps/relay exec vitest run src/modules/system/application/emergency --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-201/vitest.txt
pnpm --filter ./apps/relay exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-201/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-201/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-201/
- `vitest.txt`、`tsc.txt`、`guard.txt`
- `stop-latency.txt`（测试中每台设备 ack 耗时）

## 9. 允许修改
- `apps/relay/src/modules/system/application/emergency/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-201/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-201/` 除外，见 ownership-matrix §4）
- apps/relay/src/modules/delivery/**、routing/**、commands/**（闸门由它们调用；接线不在本卡）
- apps/relay/src/modules/system/ 下除 application/emergency 外文件（含 interfaces/http）

## 11. 依赖与阻塞
- Depends on：TASK-045
- Blocks：TASK-202
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 范围不一致：im-commands.json 写“冻结**本账号**所有智能体”，而表结构只有 `tenants.emergency_stopped_at`（组织级）。本卡按组织级实现；若需按用户账号 → 契约/迁移变更，blocked 待裁决。
  - delivery/routing/commands 未预留闸门调用点、system 接口层不在允许路径：急停端点挂载与 `/stop all` 指令接线需其所有者改动 → 报主 Agent 派接线任务；端到端 5 秒验收移至 TASK-210。
  - 契约无“查询急停状态”的 GET 端点，Web 横幅只能靠 stream 事件或 `/me` 推断 → 报缺陷。

## 12. 建议执行档位
sonnect　理由：状态位 + 帧广播 + 闸门函数，逻辑简单；5 秒时限由测试锁定。

## 13. 升级条件
- 急停范围需改为账号级或需新增端点/帧 → opus 契约审。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
小　是否小于 2 小时：否

## 15. 风险与假设
- 假设：急停期间出站冻结（保持 queued）而非丢弃（推断，“冻结”字面义）。
- 风险：恢复后积压消息集中外发可能触发渠道限速 → 由 delivery 令牌桶处理。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-201/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-201.md`）
