# TASK-205：配置导出/导入（中转，YAML，不含密钥，dry-run 差异）

```yaml
id: TASK-205
slice: S10
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Relay
tier: sonnect
size: 中
title: "配置导出/导入（中转，YAML，不含密钥，dry-run 差异）"
dependsOn: ["143"]
blocks: []
reqs: "REQ-F-034"
allowedPaths: ["apps/relay/src/modules/system/application/config-io/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S10
- 来源需求：REQ-F-034
- 来源方案：REQ-F-034（业务配置导入导出 YAML，不含密钥）；DEC-048（任何组织可自建中转，配置可迁移）

## 2. 目标
中转导出当前组织业务配置为 YAML（不含任何密钥/令牌/凭据/密码），导入时先 dry-run 返回差异，`confirm=true` 才在单事务内写入并审计；导出→导入到空组织可往返一致。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-034 SHOULD、REQ-NF-004）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §7
- 契约：
  - packages/contracts/api/relay.openapi.json：`GET /api/v1/config/export`（config.export，admin/operator）、`POST /api/v1/config/import`（config.import，仅 admin；body `yaml`、`confirm`；响应 `diff[]`、`applied`）
  - packages/contracts/schemas/entities/project/agent/channel/recipient/route/filter-rule 各 schema（导入校验）
  - packages/contracts/identity/permissions.json：`config.export`、`config.import`；`forbiddenPaths`（中转不得返回模型 Key）
  - database/migrations/relay/0001_init.sql：`projects`、`agents`、`channels`（`credential_enc`、`bot_identity_hash` 不导出）、`recipients`、`routes`、`route_*`、`filter_rules`、`barriers`
- 前置任务：TASK-143
- 前置状态：TASK-143 audit 已合并（导入写审计）。

## 4. 输出
- apps/relay/src/modules/system/application/config-io/（export、parse+validate、diff、apply 用例；字段白名单）
- apps/relay/src/modules/system/application/config-io/__tests__/ 与 `__fixtures__/`
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-205/`（见 §8）

## 5. Execution Steps
1. [ ] 定义导出白名单（而非黑名单）：projects（树）、agents（别名、适配器、项目、工作目录、写模式、非敏感 config）、channels（kind、name、非敏感 config、capabilities）、recipients（平台 id、范围、显示名，不含授权状态与绑定码）、routes（模式、源、目标、过滤引用）、filter_rules、barriers 配置；引用用稳定 slug/别名而非内部 id。
2. [ ] 明确排除：凭据、令牌哈希、bot_identity_hash、密码哈希、TOTP、推送订阅、会话、消息、审计；YAML 顶部写 `version: 1` 与导出时间。
3. [ ] 选 YAML 库并在 EVD 记录许可（待核实）；解析时禁用自定义标签/锚点炸弹（限制别名展开与大小 ≤1 MiB）。
4. [ ] 导入：逐对象按 schema 校验 → 计算 diff（add/update，默认**不删除**现有对象，删除需显式 `remove` 段，推断）→ confirm 缺省为 dry-run；confirm=true 单事务应用并写 `config.imported` 审计。
5. [ ] 写测试：导出→导入到空组织往返一致；dry-run 无写入；非法 YAML/引用缺失 → `VALIDATION_FAILED` 带字段路径；导出文本对密钥字段名与测试凭据值 grep 0 命中。
6. [ ] 运行验证命令并存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 导出→导入到空组织后再次导出，两份 YAML（去掉时间戳）完全一致。
- [ ] 导出 YAML 中对测试凭据值、`credential`、`token`、`password`、`secret`、`apiKey` 字段 grep 0 命中。
- [ ] dry-run（confirm 缺省）不改变任何表行数；confirm=true 原子应用，中途失败全部回滚（测试注入失败）。
- [ ] operator 调 import → 403；viewer 调 export → 403。
- [ ] 恶意 YAML（别名炸弹、>1 MiB）被拒绝。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-205/
pnpm --filter ./apps/relay exec vitest run src/modules/system/application/config-io --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-205/vitest.txt
pnpm --filter ./apps/relay exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-205/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-205/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-205/
- `vitest.txt`、`tsc.txt`、`guard.txt`
- `sample-export.yaml`（测试数据导出样例）
- `whitelist.md`（导出字段白名单与排除清单）

## 9. 允许修改
- `apps/relay/src/modules/system/application/config-io/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-205/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-205/` 除外，见 ownership-matrix §4）
- apps/relay/src/modules/system/ 下除 application/config-io 外文件（含 interfaces/http）
- 各业务模块内部文件（只经其公开 API 读写）

## 11. 依赖与阻塞
- Depends on：TASK-143
- Blocks：—
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 契约中 `GET /api/v1/config/export` 响应声明为 application/json 的 string 而非 YAML 媒体类型 → 按契约返回 JSON 字符串并报缺陷。
  - 其他模块未提供批量读写的公开 API，导入需直接写其表 → 违反模块边界，blocked 报主 Agent。

## 12. 建议执行档位
sonnect　理由：白名单序列化 + 校验 + diff，可逆；密钥排除由测试锁定。

## 13. 升级条件
- 需要导出含密钥的完整备份 → opus（安全语义，且与 REQ-F-034 冲突）。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：导入默认不删除（推断）。
- 假设：跨中转导入时智能体所属设备需在目标中转重新配对，导入后智能体处于 unavailable 直至设备上线（推断）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-205/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-205.md`）
