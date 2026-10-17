# TASK-062：多设备：主设备、按设备路由、离线排队提示

```yaml
id: TASK-062
slice: S3
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Relay
tier: sonnect
size: 中
title: "多设备：主设备、按设备路由、离线排队提示"
dependsOn: ["044"]
blocks: ["065", "067"]
reqs: "REQ-F-005"
allowedPaths: ["apps/relay/src/modules/devices/application/primary/**", "apps/relay/src/modules/routing/application/device-select/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S3（可演示：两台电脑、个人+公司两个中转、主/子项目树；同目录第二个写入者被拒或分到 worktree）
- 来源需求：REQ-F-005
- 来源方案：ADR-001（部署分两侧）、ADR-005（中转↔节点协议，离线排队续传）、ADR-006；architecture §4.1 devices/routing、§6.1 第 5 步“设备离线 → 排队并回提示”

## 2. 目标
实现“设为主设备”用例与路由的设备选择器：`@别名` 唯一定位到所在设备，目标设备离线时消息进入节点 outbox 排队并向发送人回“设备离线，已排队”（DEVICE_OFFLINE 语义），设备上线后按序送达。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §4.1（devices：主设备；routing：确定性选路）、§6.1
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-005-一个账号多台设备.md`
  - `docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-005-中转↔节点协议.md`
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`POST /api/v1/devices/{deviceId}/primary`（x-permission device.set_primary）、`GET /api/v1/devices`
  - `packages/contracts/schemas/entities/device.schema.json`（isPrimary、status online/offline/revoked、lastSeenAt）
  - `packages/contracts/errors/error-codes.json`：DEVICE_OFFLINE（409，retryable，ui“会话内提示：设备离线，已排队”）、DEVICE_REVOKED、NOT_FOUND、FORBIDDEN
  - `packages/contracts/events/domain-events.json`：device.online / device.offline、message.routed
  - `packages/contracts/protocol/frames/agent.prompt.schema.json`（经 node-gateway 公开 API 下发）
  - `database/migrations/relay/0001_init.sql`：`devices`（`ux_devices_primary` 部分唯一索引：每 tenant+owner 一个主设备）、`agents`（device_id、`ux_agents_alias` 租户内别名唯一）、`node_outbox`（按设备 seq 排队）
- 前置任务：TASK-044
- 前置状态：TASK-044 routing 内核已合并（`route()` 可插入设备选择步骤）；TASK-006 node-gateway 的 `sendToNode()` 支持离线入 node_outbox

## 4. 输出
- `apps/relay/src/modules/devices/application/primary/`：setPrimary 用例（同事务清旧主设备、校验所有权与吊销）+ 测试
- `apps/relay/src/modules/routing/application/device-select/`：selectDevice(agent) → {deviceId, online}；离线时生成排队提示消息 + 测试
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-062/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 阅读 TASK-044 的 routing 公开 API 与 TASK-006 的 `sendToNode()`/`isOnline()`，确认离线入队由 node-gateway 负责、本任务只做选择与提示。
2. [ ] 在 devices/application/primary 实现 setPrimary：权限 device.set_primary；已吊销设备 → DEVICE_REVOKED；单事务先清同 owner 的旧主设备再置新主设备（满足 ux_devices_primary）。
3. [ ] 在 routing/application/device-select 实现 selectDevice：别名 → agents.device_id（租户内唯一，不跨租户）；设备 revoked → DEVICE_REVOKED。
4. [ ] 设备离线：调用 node-gateway 入队并返回 `{queued:true, code:'DEVICE_OFFLINE'}`，由路由内核把固定提示“设备离线，已排队”作为 system 消息回给发送人。
5. [ ] 订阅 device.online 事件仅用于刷新缓存，不自行重放（重放由 node-gateway outbox 续传保证）。
6. [ ] 写单测：两设备两别名分别选中；离线入队返回提示；主设备切换后旧主设备 isPrimary=false；跨租户别名不可见。
7. [ ] 跑 `make guard` 验证 devices 与 routing 之间只经 index.ts 公开 API 引用。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 两台设备各一个智能体时，`@z1`/`@z2` 分别解析到对应 deviceId（单测）
- [ ] 目标设备 offline 时选择器返回 queued 且发送人收到“设备离线，已排队”提示；node_outbox 新增 1 行
- [ ] `POST /devices/{id}/primary` 后同 owner 仅 1 台 isPrimary=true；对已吊销设备返回 403 DEVICE_REVOKED
- [ ] viewer 调用 set primary 返回 403 FORBIDDEN；跨租户 deviceId 返回 404
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过

## 7. 验证命令
```bash
pnpm --filter @workfleet/relay exec vitest run src/modules/devices/application/primary src/modules/routing/application/device-select
pnpm --filter @workfleet/relay exec tsc --noEmit
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/relay/src/modules/devices/application/primary/|apps/relay/src/modules/routing/application/device-select/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-062/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-062/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `apps/relay/src/modules/devices/application/primary/**`
- `apps/relay/src/modules/routing/application/device-select/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-062/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/relay/src/modules/routing/application/modes/**（TASK-102）
- apps/relay/src/modules/devices/** 中 primary/ 以外的部分（TASK-006 所有）
- apps/relay/src/modules/node-gateway/**

## 11. 依赖与阻塞
- Depends on：TASK-044
- Blocks：TASK-065, TASK-067
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - `POST /devices/{id}/primary` 的 HTTP 路由挂载点位于 devices/interfaces（不在 allowedPaths）：若 TASK-006 未预留注册入口，停止并请求规划调整路径
  - node-gateway 未提供离线入队能力或返回值无法区分 queued
  - 需要“别名在多设备重复”语义（契约是租户内唯一）

## 12. 建议执行档位
sonnect　理由：两个小用例，均在既有内核上加一步确定性逻辑，契约明确。

## 13. 升级条件
- 需修改 routing 内核签名或 node-gateway 公开 API → 升 opus 做跨模块仲裁
- 离线排队与审批 held 的先后顺序出现冲突 → 升 opus

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- 无 U-xx 直接关联；跨境链路断线（ADR-005 风险：60 s 无帧判离线）会导致短暂误判离线，提示文案需容忍。
- 假设：主设备仅影响总控默认运行处（契约 summary），不改变普通智能体路由。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - Agent-Contract：`POST /devices/{id}/primary` 的 x-errors 为空，应含 DEVICE_REVOKED/NOT_FOUND/FORBIDDEN
  - 规划：本任务 allowedPaths 不含 devices/interfaces/http，HTTP 挂载归属需明确

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-062/
- 验证者结论：
- 遗留问题 / 跟进项编号：
