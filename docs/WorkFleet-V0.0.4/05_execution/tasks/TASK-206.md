# TASK-206：节点 doctor 与恢复密钥导出/导入

```yaml
id: TASK-206
slice: S10
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Node
tier: sonnect
size: 中
title: "节点 doctor 与恢复密钥导出/导入"
dependsOn: ["161"]
blocks: ["210"]
reqs: "REQ-F-034/035"
allowedPaths: ["apps/node/src/modules/system/application/doctor/**", "apps/node/src/modules/system/application/recovery/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S10
- 来源需求：REQ-F-034 / REQ-F-035
- 来源方案：REQ-F-034（workfleet doctor）；REQ-F-035（恢复密钥与换机）；TR-08（钥匙串回退加密文件）

## 2. 目标
节点提供 `doctor` 自检（端口、钥匙串、各中转连通、智能体可执行文件、数据库完整性）与恢复密钥导出/导入：导出恢复密钥后，在新电脑导入可恢复节点的加密数据（钥匙串中的设备令牌与模型 Key）。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-034/035 SHOULD、REQ-C-003 端口段）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §3（端口 5100–5104 仅 127.0.0.1）
  - docs/WorkFleet-V0.0.4/03_solution/technical-requirements.md（TR-05、TR-08）
- 契约：
  - packages/contracts/api/node-local.openapi.json：`GET /local/v1/doctor`（响应无类型 object）、`POST /local/v1/recovery-key/export`（“需本机系统认证确认”）、`POST /local/v1/recovery-key/import`（body 仅 `recoveryKey`，204）
  - packages/contracts/ux/ux-states.json：screen `node_local_doctor`
  - packages/contracts/errors/error-codes.json：`AGENT_UNAVAILABLE`、`VALIDATION_FAILED`
  - database/migrations/node/0001_init.sql：`relay_links.token_ref`、`model_profiles.key_ref`、`kv_settings`
- 前置任务：TASK-161
- 前置状态：TASK-161 已合并（KeyStore.health、钥匙串读写）。

## 4. 输出
- apps/node/src/modules/system/application/doctor/（检查项注册表；每项 `{id, status ok|warn|fail, detail, fixHint}`）
- apps/node/src/modules/system/application/recovery/（生成恢复密钥、加密备份包、导入解密写回钥匙串）
- 两目录 `__tests__/`
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-206/`（见 §8）

## 5. Execution Steps
1. [ ] doctor 检查项：端口 5100–5104 是否被本进程占用且只绑 127.0.0.1（他进程占用 → fail + 进程提示）；KeyStore.health（回退加密文件 → warn）；每个 relay link 的 WSS 握手 RTT 与证书有效期；已登记智能体可执行文件与版本（复用 agents 的 adapters detect）；`PRAGMA quick_check`；节点版本与协议版本。
2. [ ] doctor 输出聚合 overall 状态，单项超时 5 s 不阻塞其他项。
3. [ ] 恢复密钥设计（契约未给出数据载体，**推断方案，待裁决**）：导出时生成 256 bit 随机恢复密钥（以分组 Base32 展示），用其派生的密钥（HKDF-SHA256）以 AES-256-GCM 加密“钥匙串中全部 WorkFleet 条目”为备份包，写入节点数据目录 `recovery/backup.enc`；恢复密钥只显示一次，不入库。
4. [ ] 导出前的“本机系统认证确认”：各平台系统认证 API（Windows Hello / macOS LocalAuthentication / Linux polkit）的 Node 可用性**证据不足**；v1 默认要求在本机控制台二次确认 + 输入本机登录密码校验不可行时退化为二次确认，并在 EVD 记录实测。
5. [ ] 导入：用户把旧机数据目录（node.db + recovery/backup.enc）复制到新机后调用 import，解密并写入新机钥匙串；密钥错误 → `VALIDATION_FAILED`；成功后 doctor 应全绿（设备令牌是否仍有效取决于中转未吊销）。
6. [ ] 写测试：doctor 各项用替身覆盖 ok/warn/fail；恢复：导出→清空钥匙串替身→导入→所有 keyRef 可读；错误密钥失败且不改动现有条目。
7. [ ] 运行验证命令并存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] doctor 对端口被他进程占用、钥匙串不可用、中转不可达、智能体缺失四种故障各给出 fail/warn 与 fixHint（测试）。
- [ ] 恢复往返：导出→清空→导入后，所有 relay_links.token_ref 与 model_profiles.key_ref 对应条目恢复且值一致（替身 KeyStore 测试）。
- [ ] 错误恢复密钥导入返回 `VALIDATION_FAILED`，原有钥匙串条目不变。
- [ ] 恢复密钥不出现在 node.db、日志、备份文件明文中（grep 0 命中）。
- [ ] 三平台 CI 矩阵单测通过。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-206/
pnpm --filter ./apps/node exec vitest run src/modules/system/application/doctor src/modules/system/application/recovery --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-206/vitest.txt
pnpm --filter ./apps/node exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-206/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-206/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-206/
- `vitest.txt`、`tsc.txt`、`guard.txt`
- `doctor-sample.json`
- `recovery-design.md`（备份载体推断方案、系统认证实测结论、证据标签）
- `machine-migration.md`（两台真机换机手动记录；未做写“未实测”）

## 9. 允许修改
- `apps/node/src/modules/system/application/doctor/**`
- `apps/node/src/modules/system/application/recovery/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-206/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-206/` 除外，见 ownership-matrix §4）
- apps/node/src/modules/system/ 下除 application/doctor、application/recovery 外文件
- apps/node/src/modules/models/**、relay-link/**、agents/**（只用公开 API）
- apps/node/src/bootstrap/**（`workfleet doctor` CLI 入口不在本卡路径）

## 11. 依赖与阻塞
- Depends on：TASK-161
- Blocks：TASK-210
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 契约 `recovery-key/import` 只接收 `recoveryKey`，未定义加密数据如何到达新机：本卡按“复制数据目录”推断实现；若主 Agent 要求一体化（导入时上传备份包）→ 契约变更，blocked。
  - `workfleet doctor` 命令行入口在 bootstrap（不在允许路径）：本卡只交付用例与本机 API 委托 → CLI 接线报主 Agent。

## 12. 建议执行档位
sonnect　理由：doctor 为检查项聚合；恢复用标准原语（HKDF + AES-GCM），方案在卡内写定。

## 13. 升级条件
- 需要设计新的密钥层级或系统认证集成 → opus（密码学与平台安全）。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 证据不足：三平台系统认证 API 在 Node 中的可用性。
- 假设：换机方式为复制数据目录 + 导入恢复密钥（推断）。
- 风险：备份包与数据目录同处，恢复密钥丢失即无法恢复（在 UI 中强提示）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-206/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-206.md`）
