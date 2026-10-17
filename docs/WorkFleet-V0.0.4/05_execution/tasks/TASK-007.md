# TASK-007：节点启动层：单实例锁、relay-link（单中转）、`workfleet-node pair`、本地 outbox 续传

```yaml
id: TASK-007
slice: S0
status: todo
owner: Agent-Node
tier: sonnect
size: 大
title: "节点启动层：单实例锁、relay-link（单中转）、`workfleet-node pair`、本地 outbox 续传"
dependsOn: ["002", "003"]
blocks: ["011"]
reqs: "REQ-F-001"
allowedPaths: ["apps/node/src/bootstrap/**", "apps/node/src/core/secrets/**（钥匙串最小抽象：get/set/delete，DPAPI/Keychain/libsecret/加密文件回退；161 扩展）", "apps/node/src/core/** (除 core/db)", "apps/node/src/modules/relay-link/**", "apps/node/src/modules/system/**", "apps/node/tests/**/relay-link/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-007/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S0
- 来源需求：REQ-F-001（tasks.v1.json 原值 `REQ-F-001`）
- 来源方案：ADR-005（节点侧 seq/ack/续传）、ADR-006（配对码换设备令牌）、architecture §3（节点单实例锁、只绑 127.0.0.1:5100）/§4.2（relay-link、system）

## 2. 目标
`workfleet-node pair --relay <url> --code <8位码>` 完成配对并保存令牌；`workfleet-node start` 以单实例运行，经 relay-link 连上单个中转（hello/welcome、ack、ping、断线指数退避），本地 `relay_outbox` 在重连后续传，提供 `GET /local/v1/status`。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §3、§4.2、§7
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-005-中转↔节点协议.md、ADR-006-鉴权与权限.md
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-001、REQ-NF-003/004
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`POST /api/v1/devices/claim`（请求 `{code,name,os,nodeVersion}`，响应 `{device, deviceToken, wsUrl}`；`PAIRING_CODE_INVALID`）、`GET /api/v1/node-gateway`（`Authorization: Bearer <deviceToken>`）
  - `packages/contracts/protocol/envelope.schema.json`、`frames/hello.schema.json`、`welcome.schema.json`、`ack.schema.json`、`ping.schema.json`、`error.schema.json`（`PROTOCOL_VERSION_UNSUPPORTED`、`DEVICE_REVOKED`）
  - `packages/contracts/schemas/entities/relay-link.schema.json`（url 须 `^wss://`、status connected|connecting|disconnected|revoked）
  - `packages/contracts/api/node-local.openapi.json`：`GET /local/v1/status`（`x-auth: local`）
  - 表（node）：`relay_links`（`token_ref`、`last_acked_relay_seq`、`node_seq`）、`relay_outbox`、`relay_inbox_dedupe`、`kv_settings`
- 前置任务：TASK-002、TASK-003
- 前置状态：TASK-002（契约包）与 TASK-003（node core/db、`openTestDatabase`）已合并；联调需要 TASK-006，单测用本卡内的最小 WSS 桩（TASK-008 的 FakeRelay 合并后替换）

## 4. 输出
- `apps/node/src/bootstrap/{cli.ts,main.ts,container.ts,module-loader.ts}`（子命令 `pair`、`start`、`status`；模块按 `src/modules/*/index.ts` 的 `register(ctx)` 自动加载；`ctx` 提供 `cli.command()` 扩展点，供 agents 等模块注册子命令如 `agent add`，后续任务无需改 bootstrap）
- `apps/node/src/core/{config,logging,errors,security}/**`（`WF_NODE_DATA_DIR`、`WF_NODE_CONSOLE_PORT=5100`；`security/secret-store.ts`：`SecretStore` 端口 + 加密文件后备实现，权限 0600；OS 钥匙串实现留给 TASK-161）
- `apps/node/src/modules/relay-link/**`（单中转连接、帧收发、seq/ack、指数退避、outbox 续传、去重；`index.ts` 公开 `sendToRelay(type,payload)`、`onRelayFrame(type,handler)`）
- `apps/node/src/modules/system/**`（单实例锁 `<dataDir>/node.lock`；`GET /local/v1/status` 只绑 127.0.0.1:5100）
- 测试：`apps/node/tests/unit/modules/relay-link/**`、`apps/node/tests/integration/modules/relay-link/**`；bootstrap/core/system 测试见第 9 节测试目录

## 5. Execution Steps
1. [ ] `core/config`/`logging`/`errors`：与中转同风格（pino + traceId；错误码取 `@workfleet/contracts`）。
2. [ ] `core/security/secret-store.ts`：定义 `SecretStore{get,set,delete}`；后备实现 = `<dataDir>/secrets.enc`（AES-256-GCM，主密钥文件 0600）；令牌只经 `token_ref` 引用，不入 `relay_links`。
3. [ ] `pair` 子命令：`POST {relay}/api/v1/devices/claim`（name 默认主机名、os 映射 windows|macos|linux、nodeVersion 取 package.json）；成功写 `relay_links`（url=wsUrl、tenantId/deviceId 来自 `device`）并存令牌；400 `PAIRING_CODE_INVALID` 时打印中文提示并以退出码 2 结束。
4. [ ] `system` 单实例锁：独占创建 `node.lock`（含 pid），已存在且 pid 存活→第二个实例打印“已有实例运行”并退出码 3；崩溃残留锁按 pid 判活自动清除。
5. [ ] `relay-link`：连接 `wsUrl` 带 `Authorization: Bearer`；发 `hello{protocolVersion:1,nodeVersion,os,lastAckedRelaySeq,agents:[]}`；收 `welcome` 后从 `relay_outbox` 重放 seq>`welcome.lastAckedNodeSeq` 的帧。
6. [ ] 收发规则：出站业务帧 seq=`node_seq+1` 先写 `relay_outbox` 再发；入站按 `(relay_link_id,idempotencyKey)` 去重后分发并累积回 `ack`；收 `ack` 置 `acked_at`；每 20 s `ping`，60 s 无帧主动断开重连。
7. [ ] 退避：1 s 起指数退避上限 60 s + 抖动；收到 `DEVICE_REVOKED`→`relay_links.status=revoked` 并停止重连。
8. [ ] `GET /local/v1/status`：返回版本、relay-link 状态（connected/connecting/disconnected/revoked）、排队帧数；监听地址固定 127.0.0.1。
9. [ ] 写测试（最小 WSS 桩）：配对成功/码错误；单实例第二进程退出码 3；断线期间 `sendToRelay` 的帧在重连后按序重放；重复入站帧只分发一次；吊销后不再重连。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`pnpm -F @workfleet/node cli pair --relay http://127.0.0.1:5110 --code <有效码>` 退出码 0，`relay_links` 新增 1 行且 `token_ref` 非空、库内无明文令牌；错误码退出码 2 并打印 `PAIRING_CODE_INVALID` 对应提示。
- [ ] AC-2：同一数据目录启动第二个 `start` 进程退出码 3（单实例，REQ-F-001）。
- [ ] AC-3：WSS 桩断开 → 节点在 ≤60 s 内按退避重连；断线期间产生的 3 个出站帧在重连后按 seq 顺序全部送达，无重复（REQ-NF-003）。
- [ ] AC-4：入站相同 `idempotencyKey` 帧两次，订阅者回调 1 次，`relay_inbox_dedupe` 1 行，且回 `ack.upToSeq` 单调不减。
- [ ] AC-5：`curl http://127.0.0.1:5100/local/v1/status` 返回 relay-link `connected`；`ss -ltn` 显示仅监听 127.0.0.1（REQ-NF-004）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/node test tests/unit/modules/relay-link tests/integration/modules/relay-link
pnpm -F @workfleet/node test tests/unit/bootstrap tests/unit/core tests/unit/modules/system
pnpm -F @workfleet/node typecheck
# 与 TASK-006 联调（可选）：先在中转生成配对码
pnpm -F @workfleet/node cli pair --relay http://127.0.0.1:5110 --code ABCD2345
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-007/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/node/src/bootstrap/**`
- `apps/node/src/core/** (除 core/db)`
- `apps/node/src/modules/relay-link/**`
- `apps/node/src/modules/system/**`
- `apps/node/tests/**/relay-link/**`
- 明确写出的测试目录（本模块专属；allowedPaths 未含测试路径，按任务指令 §3 在此显式声明，执行前须经主 Agent 确认）：
  - `apps/node/tests/unit/bootstrap/**`
  - `apps/node/tests/unit/core/**（不含 core/db）`
  - `apps/node/tests/unit/modules/system/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-007/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-007/` 除外）
- `apps/node/src/core/db/**`（TASK-003）
- `apps/node/src/modules/agents/**`（TASK-011/021）
- `apps/node/src/modules/sessions/**`（TASK-023）
- `apps/relay/**`、`apps/web/**`、`packages/testkit/**`

## 11. 依赖与阻塞
- Depends on：TASK-002, TASK-003
- Blocks：TASK-011
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - `apps/node/package.json` 的 `bin`/依赖由 TASK-001 所有；若缺 `ws`/`better-sqlite3` 等依赖 → blocked 提单给 Agent-Guard
  - TASK-161 的钥匙串抽象（models 模块）与本卡 `core/security/SecretStore` 职责重叠 → 本卡只做端口 + 加密文件后备；若主 Agent 要求统一到 models 模块则 blocked
  - 节点本机 API（127.0.0.1:5100）的承载模块 `local-console` 在任何任务 allowedPaths 中都不存在 → 本卡在 `bootstrap` 起最小 HTTP 服务、`system` 提供 `/local/v1/status`；其余 `/local/v1/*` 归属需主 Agent 裁定
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：协议语义已由 ADR-005 与 TASK-006 定型，节点侧是对偶实现，sonnect 可完成；可靠性用例由测试兜底。

## 13. 升级条件
- 续传/去重测试连续 2 次不稳定（偶发重复或丢帧）→ 升 opus 复核状态机
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
大　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-04）：节点到香港中转的链路可能不稳定，以退避 + 续传应对，指标由 TASK-041/210 测量。
- 假设（NON_BLOCKING）：Windows 单实例锁使用文件锁 + pid 判活即可（Job Object 留给 TASK-021 进程树）——待三平台 CI 实测。
- 风险：多中转（TASK-063）会重构 relay-link；本卡接口按“每个 relay_link 一个实例”设计以降低返工。
- 风险：`relay-link.schema.json` 要求 url 匹配 `^wss://`，本地/E2E 中转（5110–5119，无 TLS）为 `ws://` → 测试环境以配置开关放行 `ws://127.0.0.1`，生产强制 wss；契约冲突已报告。
- 本卡不涉及 U-02、U-03、U-05…U-07。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-007/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
