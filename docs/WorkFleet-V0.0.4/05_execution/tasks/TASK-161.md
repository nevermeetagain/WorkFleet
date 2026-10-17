# TASK-161：models：钥匙串抽象（DPAPI/Keychain/libsecret/加密文件）、模型配置 CRUD、用量与费用

```yaml
id: TASK-161
slice: S8
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Node
tier: opus
size: 大
title: "models：钥匙串抽象（DPAPI/Keychain/libsecret/加密文件）、模型配置 CRUD、用量与费用"
dependsOn: ["063"]
blocks: ["162", "165", "206"]
reqs: "REQ-F-026"
allowedPaths: ["apps/node/src/modules/models/**", "apps/node/src/core/secrets/**（扩展 007 的抽象）"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S8
- 来源需求：REQ-F-026
- 来源方案：ADR-013（总控模型调用）；DEC-044（模型配置归用户、Key 存本机钥匙串、费用估算）；DEC-043（每日硬上限）；TR-08（DPAPI/Keychain/libsecret 回退加密文件）

## 2. 目标
在节点实现钥匙串抽象（Windows DPAPI / macOS Keychain / Linux libsecret / 回退加密文件）、模型配置 CRUD（apiKey 只在请求中出现一次，入库只存 `keyRef`）、用量记录与费用估算、日/月上限判定与 `budget.exceeded` 事件；Key 明文不出现在 node.db、日志、任何 API 响应中。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-013-总控的模型调用.md
  - docs/WorkFleet-V0.0.4/03_solution/technical-requirements.md（TR-08）
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-026、REQ-NF-004/010、REQ-C-006）
  - docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md（DEC-043、DEC-044、DEC-045）
- 契约：
  - packages/contracts/schemas/entities/model-profile.schema.json（provider、baseUrl、model、keyRef、params、pricing.inputPerMTokMicros/outputPerMTokMicros/currency、limits.dailyMicros/monthlyMicros/onExceed）
  - packages/contracts/api/node-local.openapi.json：`GET/POST /local/v1/model-profiles`、`PATCH/DELETE /local/v1/model-profiles/{modelProfileId}`、`POST /local/v1/model-profiles/{modelProfileId}/test`、`GET /local/v1/usage`
  - packages/contracts/events/domain-events.json：`budget.exceeded`（emitter node.models，幂等键 modelProfileId+period）
  - packages/contracts/schemas/common/money.schema.json（amountMicros + currency，ADR-012）；errors/error-codes.json：`BUDGET_EXCEEDED`、`MODEL_PROVIDER_ERROR`、`VALIDATION_FAILED`、`CONFLICT`
  - database/migrations/node/0001_init.sql：`model_profiles`（key_ref、version、deleted_at）、`model_usage`、`kv_settings`
- 前置任务：TASK-063
- 前置状态：TASK-063 已合并（节点 core、local-console 路由注册机制可用）。

## 4. 输出
- apps/node/src/modules/models/domain/（ModelProfile、费用计算、预算期间判定，纯函数）
- apps/node/src/modules/models/application/（profile CRUD、recordUsage、checkBudget、usage 查询）
- apps/node/src/modules/models/infrastructure/keystore/（`KeyStore` 端口 + windows-dpapi、macos-keychain、linux-libsecret、encrypted-file 四个实现 + 选择器）
- apps/node/src/modules/models/infrastructure/persistence/、interfaces/http/、index.ts
- apps/node/src/modules/models/**/__tests__/
- （不含 infrastructure/providers/**，那是 TASK-162 的）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-161/`（见 §8）

## 5. Execution Steps
1. [ ] 钥匙串选型实测：在三平台评估候选（如 `@napi-rs/keyring` 等原生绑定、或调用系统 CLI `security`/`secret-tool`/PowerShell DPAPI）——维护状态、许可、预编译包；**证据不足，须实测**，结论与许可写入 EVD-161/keystore-choice.md，不得凭印象选定。
2. [ ] 定义 `KeyStore` 端口（set/get/delete/health）；实现选择器：首选 OS 钥匙串，不可用（如无桌面会话的 Linux）时回退 encrypted-file（AES-256-GCM，主密钥 32 字节随机存 0600 文件；该回退为降级，`health()` 返回 warn 供 doctor 显示）。
3. [ ] 实现 profile CRUD：POST 校验 profile（ajv）→ apiKey 写钥匙串得到 `keyRef` → 入库；PATCH 支持可选 apiKey 轮换与乐观锁 `version`；DELETE 软删除并删除钥匙串条目；GET 永不返回 Key。
4. [ ] pino redact：对 `apiKey`、`authorization`、`x-api-key` 路径脱敏；HTTP 层拒绝把 apiKey 写入访问日志。
5. [ ] 实现费用：`costMicros = round(inTok × inputPerMTokMicros / 1e6 + outTok × outputPerMTokMicros / 1e6)`；`recordUsage(profileId, purpose, usage)` 写 `model_usage`。
6. [ ] 实现 `checkBudget(profileId)`：按节点本地时区（推断，写 EVD）汇总当日/当月 cost，≥ 上限时返回 `{exceeded, onExceed}` 并发出 `budget.exceeded`（同期幂等）；`GET /local/v1/usage` 返回日/月汇总与上限。
7. [ ] 实现 `/test` 连通性测试端点：调用 162 的 provider 接口（162 未合并前用接口桩，测试用 ReplayProvider）。
8. [ ] 写测试：四种 KeyStore 用内存/临时目录替身做契约测试；真实 OS 钥匙串测试在 CI 三平台矩阵中以 `WF_KEYSTORE_REAL=1` 运行（Linux 无 secret service 时断言回退）；Key 泄露测试：创建 profile 后 grep node.db 文件与日志 0 命中。
9. [ ] 运行验证命令并存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 创建含测试 Key 的 profile 后：node.db 文件、节点日志、GET/PATCH 响应中 grep 测试 Key 均 0 命中（自动化）。
- [ ] 四个 KeyStore 实现通过同一套契约测试；无钥匙串环境自动回退加密文件且 `health()=warn`。
- [ ] 费用计算单测：给定 usage 与单价，costMicros 精确到整数（含 0 单价、百万级 token 边界）。
- [ ] 日/月上限：累计超过 dailyMicros 时 `checkBudget` 返回 exceeded，`budget.exceeded` 同一日只发 1 次（测试）。
- [ ] DELETE 后钥匙串条目被删除（替身断言）；PATCH 旧 version → `CONFLICT`。
- [ ] CI 三平台矩阵单测通过（ubuntu/windows/macos）。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-161/
pnpm --filter ./apps/node exec vitest run src/modules/models --reporter=verbose --exclude 'src/modules/models/infrastructure/providers/**' | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-161/vitest.txt
WF_KEYSTORE_REAL=1 pnpm --filter ./apps/node exec vitest run src/modules/models/infrastructure/keystore | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-161/keystore-real-$(uname -s).txt
pnpm --filter ./apps/node exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-161/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-161/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-161/
- `vitest.txt`、`tsc.txt`、`guard.txt`
- `keystore-real-<OS>.txt`（三平台各一份，来自 CI 矩阵 artifact）
- `keystore-choice.md`（候选、许可、维护状态、实测结论，带证据标签）

## 9. 允许修改
- `apps/node/src/modules/models/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-161/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-161/` 除外，见 ownership-matrix §4）
- apps/node/src/modules/models/infrastructure/providers/**（TASK-162）
- apps/node/src/modules/supervisor/**
- apps/relay/**（中转不得出现任何模型 Key 相关代码，REQ-C-006）

## 11. 依赖与阻塞
- Depends on：TASK-063
- Blocks：TASK-162, TASK-165, TASK-206
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 三平台均无满足许可（Apache-2.0 兼容）且可预编译的钥匙串方案：标 blocked，附实测记录，交 opus/用户裁决（例如接受只用加密文件）。
  - macOS Keychain 首次访问弹授权框导致 CI 无法无人值守：真实钥匙串测试改为手动证据，需主 Agent 确认。

## 12. 建议执行档位
opus　理由：Key 安全边界 + 三平台原生依赖选型属不可逆高风险（DEC-044 硬约束）。

## 13. 升级条件
- 需要把 Key 或其派生物传出节点、或改 model-profile 契约 → fable。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
大　是否小于 2 小时：否　选型实测 + 四实现 + CRUD + 费用，约 2 天。

## 15. 风险与假设
- 证据不足：各钥匙串库的维护状态与三平台预编译可用性，须实测。
- 假设：预算日界按节点本地时区（推断，待裁决）。
- 假设：encrypted-file 回退的主密钥与数据同盘存放只防误读、不防本机管理员（在 doctor 中提示）。
- 风险：提供方不返回 usage 时无法计费 → 由 162 标记 `usage=null`，本卡按 0 计并告警。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-161/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-161.md`）
