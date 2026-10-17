# TASK-202：急停（节点）：冻结所有会话与队列、恢复

```yaml
id: TASK-202
slice: S10
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Node
tier: sonnect
size: 小
title: "急停（节点）：冻结所有会话与队列、恢复"
dependsOn: ["201"]
blocks: ["210"]
reqs: "REQ-F-033"
allowedPaths: ["apps/node/src/modules/system/application/emergency/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S10
- 来源需求：REQ-F-033
- 来源方案：G9 急停；REQ-F-033；architecture §4.2 system、agents（进程监管）

## 2. 目标
节点收到 `emergency.stop` 后立即取消所有运行中的智能体轮次、冻结每会话 prompt 队列与总控/会议计时器、拒绝新 prompt，状态持久化（重启后仍冻结）；收到 `emergency.resume` 后恢复；节点内生效 ≤1 秒（为端到端 5 秒留余量）。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-033）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.2
  - docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md（DEC-048 多中转隔离）
- 契约：
  - packages/contracts/protocol/frames/emergency.stop.schema.json、emergency.resume.schema.json、ack.schema.json、error.schema.json、agent.status.schema.json（status `stopped`）
  - packages/contracts/errors/error-codes.json：`EMERGENCY_STOPPED`
  - database/migrations/node/0001_init.sql：`prompt_queue`（state）、`sessions`、`kv_settings`（持久化急停状态）
- 前置任务：TASK-201
- 前置状态：TASK-201 已合并（帧已下发）；agents 模块提供按会话 cancel 的公开 API（TASK-021）。

## 4. 输出
- apps/node/src/modules/system/application/emergency/（onStop、onResume、isFrozen(relayLinkId)、状态持久化）
- apps/node/src/modules/system/application/emergency/__tests__/
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-202/`（见 §8）

## 5. Execution Steps
1. [ ] 定义范围：急停按发出该帧的中转连接（relay link 命名空间）生效——个人中转的急停不冻结公司中转的智能体（DEC-048 隔离，推断），写入 EVD 待裁决。
2. [ ] onStop：持久化 `kv_settings['emergency.<relayLinkId>']` → 对该命名空间所有运行中会话调用 ACP cancel → 暂停 prompt_queue 工作者（queued 保持 queued）→ 暂停总控 merge 定时器与会议轮次计时 → 上报 `agent.status(stopped)` → ack。
3. [ ] 闸门：冻结期间收到的新 `agent.prompt` 入队但不执行，并回 `error` 帧 `EMERGENCY_STOPPED`（或仅入队，按 201 的中转侧闸门为准，二者择一并记录）。
4. [ ] onResume：清除状态 → 恢复工作者与计时器 → 上报 idle → ack。
5. [ ] 启动时读取持久化状态，保证重启后仍冻结。
6. [ ] 写测试：3 个 FakeAgent 运行中 → stop → 1 s 内全部收到 cancel、队列不再出队；重启节点仍冻结；resume 后队列按序继续；另一 relay link 的智能体不受影响。
7. [ ] 运行验证命令并存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] stop 帧到达后 ≤1 s 内所有运行会话收到 cancel，prompt_queue 不再出队（测试计时）。
- [ ] 冻结状态在节点重启后保持（测试）。
- [ ] resume 后排队 prompt 按原顺序执行，0 丢失。
- [ ] 另一中转连接命名空间的智能体不受影响（多中转用例）。
- [ ] `make guard` 通过。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-202/
pnpm --filter ./apps/node exec vitest run src/modules/system/application/emergency --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-202/vitest.txt
pnpm --filter ./apps/node exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-202/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-202/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-202/
- `vitest.txt`、`tsc.txt`、`guard.txt`
- `scope-decision.md`（按 relay link 生效的推断与待裁决）

## 9. 允许修改
- `apps/node/src/modules/system/application/emergency/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-202/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-202/` 除外，见 ownership-matrix §4）
- apps/node/src/modules/agents/**、sessions/**、supervisor/**、meetings/**、relay-link/**（只用公开 API）
- apps/node/src/modules/system/ 下除 application/emergency 外文件

## 11. 依赖与阻塞
- Depends on：TASK-201
- Blocks：TASK-210
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - relay-link 帧分发不在允许路径：若 TASK-063 未提供按帧类型注册处理器 → blocked。
  - supervisor/meetings 未暴露暂停/恢复计时器的公开 API → 该部分 blocked 并报缺口（智能体 cancel 与队列冻结仍可交付）。

## 12. 建议执行档位
sonnect　理由：状态切换 + 调用已有 cancel，逻辑小；时限与持久化由测试锁定。

## 13. 升级条件
- 急停范围（单 relay link vs 全节点）需改为全节点并跨命名空间 → opus（隔离语义）。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
小　是否小于 2 小时：否

## 15. 风险与假设
- 假设：按 relay link 命名空间生效（推断）。
- 风险：部分 ACP 智能体对 cancel 响应慢 → 超过 1 s 时强制杀进程树（Windows Job Object / POSIX 进程组，TASK-021 能力）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-202/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-202.md`）
