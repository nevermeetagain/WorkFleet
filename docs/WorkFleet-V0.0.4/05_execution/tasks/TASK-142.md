# TASK-142：permissions-filter：接收人×业务线×字段过滤与脱敏

```yaml
id: TASK-142
slice: S7
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Relay
tier: opus
size: 中
title: "permissions-filter：接收人×业务线×字段过滤与脱敏"
dependsOn: ["102"]
blocks: ["145"]
reqs: "REQ-F-027"
allowedPaths: ["apps/relay/src/modules/permissions-filter/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S7
- 来源需求：REQ-F-027
- 来源方案：DEC-047（G3 接收人级权限升 MUST）；architecture §4.1 permissions-filter（出站前最后一道）；§6.1 第 7 步

## 2. 目标
实现 `filterOutbound(message, recipient, route)`：按“接收人 × 业务线 × 字段”规则对同一条出站消息为每个接收人产出不同的可见内容（allow_fields / mask_fields / drop_message，maskStyle full/partial/hash），并把命中的规则 id 写入投递的 `filtersApplied`；脱敏有单测。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-027、REQ-F-016 dry-run）
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §4.1、§6.1
  - docs/WorkFleet-V0.0.4/00_governance/glossary.md（过滤规则≠权限）
  - docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md（DEC-047）
- 契约：
  - packages/contracts/schemas/entities/filter-rule.schema.json（`match.recipientIds`、`match.businessLines`、`action`、`fields`、`maskStyle`）
  - packages/contracts/schemas/entities/message-body.schema.json（`blocks`、`tags`、`fields`——“结构化字段，供过滤与脱敏（G3）”）
  - packages/contracts/schemas/entities/delivery.schema.json（`filtersApplied`、`status=suppressed`）
  - packages/contracts/api/relay.openapi.json：`GET/POST /api/v1/filter-rules`、`PATCH/DELETE /api/v1/filter-rules/{filterRuleId}`（filter.read/filter.write）、`POST /api/v1/routes/dry-run`（返回“过滤后的各接收人可见内容”）
  - packages/contracts/identity/permissions.json：`filter.read`（三角色）、`filter.write`（仅 admin）
  - database/migrations/relay/0001_init.sql：`filter_rules`、`route_filters(ord)`、`deliveries.filters_applied`
- 前置任务：TASK-102
- 前置状态：TASK-102（routing 模式）与 TASK-045（delivery outbox）已合并，routing 在入队前可调用 `permissions-filter` 公开 API。

## 4. 输出
- apps/relay/src/modules/permissions-filter/domain/（规则匹配、字段裁剪、三种脱敏函数，纯函数）
- apps/relay/src/modules/permissions-filter/application/（`filterOutbound`、规则 CRUD 用例、dry-run 预览用例）
- apps/relay/src/modules/permissions-filter/infrastructure/（filter_rules 仓储）
- apps/relay/src/modules/permissions-filter/interfaces/http/（filter-rules 4 个端点）
- apps/relay/src/modules/permissions-filter/index.ts（只导出 `filterOutbound`、`previewForRecipients`）
- apps/relay/src/modules/permissions-filter/**/__tests__/
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-142/`（见 §8）

## 5. Execution Steps
1. [ ] 在 EVD 写“业务线来源”决定：契约 message-body 无 businessLine 字段，默认取 `body.fields.businessLine`，缺失时视为空业务线（只匹配不限业务线的规则）；标“推断，待裁决”。
2. [ ] domain：实现规则选择（tenant 规则中 `match` 命中接收人与业务线者 + 绑定上 `route_filters` 按 `ord` 排序），多条命中时 drop_message 优先，其次 allow_fields 取交集，再应用 mask_fields。
3. [ ] domain：实现脱敏：full→`***`；partial→保留首尾各 1 个字符（长度≤2 全遮）；hash→`sha256` 前 8 位十六进制加前缀 `#`；对 `body.fields` 生效，并把被遮字段的原值在 paragraph/list/table/kpi 文本中同步替换。
4. [ ] application：`filterOutbound` 返回 `{ body | null, filtersApplied[] }`，`null` 表示 drop（调用方把投递置 `suppressed`）；纯同步、无 IO，便于在 delivery 前调用。
5. [ ] application：实现 filter-rules CRUD（filter.write 仅 admin；`fields` 非空校验；软删除）与 `previewForRecipients` 供 `/routes/dry-run` 使用。
6. [ ] 写单测：三种 action × 三种 maskStyle × 有/无业务线；同一条“汇总”消息发给“老板”（allow_fields: 汇总字段）与“数据部”（不过滤明细）得到不同可见字段（REQ-F-027 原句用例）。
7. [ ] 写集成测试：规则 CRUD 端点权限（viewer 写 → 403），dry-run 返回每个接收人的过滤后内容，`filtersApplied` 记录规则 id。
8. [ ] 运行验证命令并存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] REQ-F-027 用例：同一汇总发给两个接收人得到不同可见字段，自动化断言逐字段通过。
- [ ] full/partial/hash 三种脱敏各有边界单测（空串、1 字符、中文、emoji），全部通过。
- [ ] drop_message 命中时 `filterOutbound` 返回 null，`filtersApplied` 含该规则 id。
- [ ] 被遮字段原值不出现在任何文本块中（单测对 IR 全部 block 类型做 grep 断言）。
- [ ] filter-rules 端点权限与 permissions.json 一致（viewer/operator 写 → 403）。
- [ ] `make guard` 通过；permissions-filter 不依赖 delivery/routing 内部文件。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-142/
pnpm --filter ./apps/relay exec vitest run src/modules/permissions-filter --coverage --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-142/vitest.txt
pnpm --filter ./apps/relay exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-142/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-142/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-142/
- `vitest.txt`（含 coverage 摘要，domain 行覆盖 ≥90% 为目标）
- `business-line-decision.md`
- `tsc.txt`、`guard.txt`

## 9. 允许修改
- `apps/relay/src/modules/permissions-filter/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-142/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-142/` 除外，见 ownership-matrix §4）
- apps/relay/src/modules/routing/**、delivery/**（调用方由其所有者接线）
- apps/relay/src/modules/audit/**

## 11. 依赖与阻塞
- Depends on：TASK-102
- Blocks：TASK-145
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 契约缺“业务线”来源字段：若主 Agent/用户裁定的来源不是 `body.fields.businessLine`，需契约变更 → 暂停相关部分。
  - routing（TASK-044/102）或 delivery（TASK-045）未在入队前预留 `filterOutbound` 调用点：本卡不得改它们 → blocked，报主 Agent 加接线任务。

## 12. 建议执行档位
opus　理由：出站数据泄露防线，属安全语义（cost-budget：安全审查/高风险用 opus），S7 券内已计。

## 13. 升级条件
- 需要改 filter-rule 契约或 message-body 增字段 → fable（推翻冻结契约）。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否　规则引擎小而关键，测试量大。

## 15. 风险与假设
- 假设：多规则冲突按 drop > allow 交集 > mask 处理（推断）。
- 风险：自由文本中出现的敏感值只能按已知字段值替换，无法识别未结构化的敏感信息 → 在控制台文案中说明“只对结构化字段生效”。
- 假设：业务线取 `body.fields.businessLine`（推断，待裁决）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-142/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-142.md`）
