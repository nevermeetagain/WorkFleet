# TASK-063：节点多中转：relay-link 管理、命名空间隔离、各自凭据

```yaml
id: TASK-063
slice: S3
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Node
tier: opus
size: 大
title: "节点多中转：relay-link 管理、命名空间隔离、各自凭据"
dependsOn: ["023"]
blocks: ["066", "067", "144", "161"]
reqs: "REQ-F-006"
allowedPaths: ["apps/node/src/modules/relay-link/**", "apps/node/src/modules/agents/application/namespace/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S3（可演示：两台电脑、个人+公司两个中转、主/子项目树；同目录第二个写入者被拒或分到 worktree）
- 来源需求：REQ-F-006
- 来源方案：ADR-001、ADR-005、ADR-006；DEC-048（个人/公司双中转）；architecture §4.2 `relay-link`

## 2. 目标
本机节点可同时维护 ≥2 条中转连接，每条连接独立设备令牌、独立 seq/ack 与 outbox、独立智能体命名空间；任一中转的帧只能触达本连接命名空间内的智能体与会话。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §4.2（relay-link：1..N 中转、独立凭据、独立路由命名空间、指数退避+续传）、§7
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-006-多中转连接.md`
  - `docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-005-中转↔节点协议.md`（心跳 20 s、60 s 判断线、帧 ≤1 MiB）
- 契约：
  - `packages/contracts/api/node-local.openapi.json`：`GET/POST /local/v1/relay-links`（POST body url+pairingCode+label，201 返回 relay-link）、`DELETE /local/v1/relay-links/{relayLinkId}`
  - `packages/contracts/api/relay.openapi.json`：`POST /api/v1/devices/claim`（配对码换设备令牌）、`GET /api/v1/node-gateway`（Bearer 设备令牌）
  - `packages/contracts/schemas/entities/relay-link.schema.json`（url `^wss://`、status connected/connecting/disconnected/revoked）
  - `packages/contracts/protocol/envelope.schema.json` + `frames/hello|welcome|ack|ping|agents.sync|error`（每方向 seq、lastAcked 续传）
  - `packages/contracts/errors/error-codes.json`：PAIRING_CODE_INVALID、DEVICE_REVOKED、PROTOCOL_VERSION_UNSUPPORTED、UNAUTHENTICATED
  - `database/migrations/node/0001_init.sql`：`relay_links`（token_ref 钥匙串条目名、`ux_relay_links_url_tenant`）、`agents.relay_link_id`、`relay_outbox`/`relay_inbox_dedupe`（按 relay_link_id 分区）、`sessions`
- 前置任务：TASK-023
- 前置状态：TASK-023 已合并（sessions 按 conversation 管理）；TASK-007 单中转 relay-link 与 `workfleet-node pair` 可用

## 4. 输出
- `apps/node/src/modules/relay-link/`：LinkManager（1..N 连接生命周期、退避重连、按 link 的 seq/outbox/dedupe）、link 仓储、本机 API 处理器（relay-links 三个端点）
- `apps/node/src/modules/agents/application/namespace/`：NamespaceGuard（frame → relayLinkId → 只解析本 link 的 agents）+ 测试
- `apps/node/src/modules/relay-link/__tests__/`：双 FakeRelay 隔离测试
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-063/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 梳理 TASK-007 单连接实现，抽出 Link 对象（url、tenantId、deviceId、tokenRef、seq 状态），改为 Map<relayLinkId, Link>。
2. [ ] 实现 `POST /local/v1/relay-links`：调用目标中转 `/api/v1/devices/claim` 换令牌 → 令牌写入钥匙串（只存 token_ref）→ 插入 relay_links；同 (url, tenantId) 重复 → 409 CONFLICT。
3. [ ] 每条 Link 独立维护 node_seq/last_acked_relay_seq、relay_outbox、relay_inbox_dedupe；hello 携带本 link 命名空间内 agents。
4. [ ] 实现断线指数退避（含抖动、上限）与续传；DEVICE_REVOKED → status=revoked 且不再重连；PROTOCOL_VERSION_UNSUPPORTED → 停止并在 status 上报。
5. [ ] 在 agents/application/namespace 实现 NamespaceGuard：入站帧只能按 (relayLinkId, agentId) 查找；跨 link 的 agentId → 回 error 帧 NOT_FOUND，不泄露存在性。
6. [ ] `DELETE /local/v1/relay-links/{id}`：断开、删除钥匙串条目、标记该 link 下 agents deleted_at，不影响其他 link。
7. [ ] 写隔离测试：两个 FakeRelay（端口 5110/5111）同时连接，A 下发的 agent.prompt 无法驱动 B 的智能体；A 断线不影响 B 收发；日志/outbox 中无对方数据。
8. [ ] 在三平台 CI 矩阵跑单测（ADR-011），把双连接时序日志写入证据。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 同一节点同时连接两个 FakeRelay，`GET /local/v1/relay-links` 返回 2 条 connected，响应通过 relay-link.schema.json 校验
- [ ] Relay A 发往 Relay B 命名空间 agentId 的 agent.prompt 被拒（error 帧 NOT_FOUND），B 侧无任何副作用（测试断言）
- [ ] 断开 A 后 B 的收发不中断；A 恢复后从 lastAcked+1 续传，无重复执行（dedupe 断言）
- [ ] relay_links 表与日志中 grep 不到设备令牌明文（只存 token_ref）
- [ ] DELETE 一条 link 后另一条 link 的 agents、sessions 不变
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过

## 7. 验证命令
```bash
pnpm --filter @workfleet/node exec vitest run src/modules/relay-link src/modules/agents/application/namespace
pnpm --filter @workfleet/node exec tsc --noEmit
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/node/src/modules/relay-link/|apps/node/src/modules/agents/application/namespace/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-063/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-063/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `apps/node/src/modules/relay-link/** `
- `apps/node/src/modules/agents/application/namespace/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-063/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/node/src/modules/agents/** 中 application/namespace/ 以外部分（TASK-021/022 所有）
- apps/node/src/modules/sessions/**（TASK-023）
- apps/node/src/core/**

## 11. 依赖与阻塞
- Depends on：TASK-023
- Blocks：TASK-066, TASK-067, TASK-144, TASK-161
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 设备令牌需要钥匙串，但钥匙串抽象排在 TASK-161（依赖本任务之后）：若 TASK-007 未在 core 提供可用的令牌安全存储，停止并请求规划裁决依赖顺序
  - TASK-021 的入站帧分发未暴露可插入 NamespaceGuard 的钩子（需修改 agents 其它目录）
  - tasks.v1.json 中 allowedPaths `apps/node/src/modules/relay-link/** `带尾随空格，若路径守卫脚本因此误判越界，按 relay-link/** 处理并登记

## 12. 建议执行档位
opus　理由：涉及多租户隔离与凭据，越权即数据泄露，且是节点执行链关键路径（dag.md），需 opus。

## 13. 升级条件
- 需要修改协议帧或新增 hello 字段（例如 relayLinkId）→ 升 fable（冻结契约变更）
- 钥匙串依赖顺序无法在本切片内解决 → 提交规划变更

## 14. 预估规模
大(≈2d)　是否小于 2 小时：否

## 15. 风险与假设
- 无 U-xx 直接关联；与 U-04（香港中转连通性）相关：跨境断线频繁时退避策略需在证据中记录实际重连次数。
- 假设：每条中转连接对应一个独立 device 记录（同一台电脑在两个中转上是两个 deviceId）。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - 规划：TASK-063 allowedPaths 首项有尾随空格（ownership-matrix 中同样重复出现 `relay-link/** `），需清理
  - 规划：钥匙串抽象（TASK-161）晚于本任务，令牌存储依赖关系倒置

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-063/
- 验证者结论：
- 遗留问题 / 跟进项编号：
