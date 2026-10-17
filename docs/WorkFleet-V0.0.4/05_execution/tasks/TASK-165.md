# TASK-165：Web 本机：模型配置、用量看板、总控设置

```yaml
id: TASK-165
slice: S8
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-App
tier: sonnect
size: 中
title: "Web 本机：模型配置、用量看板、总控设置"
dependsOn: ["066", "161"]
blocks: ["166", "183"]
reqs: "REQ-F-026"
allowedPaths: ["apps/web/src/targets/node/models/**", "apps/web/src/targets/node/supervisor/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S8
- 来源需求：REQ-F-026
- 来源方案：ADR-008；DEC-044（在线编辑模型配置）；DEC-045（v1 只保留系统提示词，技能文件上传移至 v3）

## 2. 目标
在本机控制台（node 构建目标）提供模型配置管理（含 apiKey 一次性输入、连通性测试）、用量与费用看板（日/月 vs 上限）、总控设置（模型选择、规则、系统提示词、降级横幅）；apiKey 永不回显、不落浏览器存储。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-008-前端.md
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-026、REQ-NF-011）
  - docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md（DEC-044、DEC-045）
- 契约：
  - packages/contracts/api/node-local.openapi.json：`/local/v1/model-profiles`（GET/POST）、`/local/v1/model-profiles/{modelProfileId}`（PATCH/DELETE）、`/{id}/test`、`/local/v1/usage`、`/local/v1/supervisor`（GET/PUT）
  - packages/contracts/schemas/entities/model-profile.schema.json（表单字段与约束，rjsf 渲染）
  - packages/contracts/ux/ux-states.json：screen `node_local_models`（6 态）
  - packages/contracts/errors/error-codes.json：`BUDGET_EXCEEDED`（总控横幅）、`MODEL_PROVIDER_ERROR`（Toast + 重试）、`VALIDATION_FAILED`
- 前置任务：TASK-066, TASK-161
- 前置状态：TASK-066 本机控制台骨架与 TASK-161 本机 API 已合并。

## 4. 输出
- apps/web/src/targets/node/models/（配置列表、表单、Key 输入、测试按钮、用量看板）
- apps/web/src/targets/node/supervisor/（总控设置页、规则编辑器、系统提示词编辑、降级横幅组件）
- 两目录内 `__tests__/*.test.tsx`（vitest + Testing Library + MSW）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-165/`（见 §8）

## 5. Execution Steps
1. [ ] 用 @rjsf 按 model-profile.schema.json 渲染表单（去掉 id/keyRef/createdAt），apiKey 用独立 password 输入，仅在 POST/PATCH 请求体出现一次。
2. [ ] 确保 apiKey 不进入 TanStack Query 缓存、Zustand、localStorage/IndexedDB（提交后立即清空字段）；列表与详情只显示 `keyRef` 与“已保存”。
3. [ ] 实现连通性测试按钮（显示延迟与 usage）与删除确认（提示“将清除钥匙串条目”）。
4. [ ] 用量看板：调用 `/local/v1/usage` 显示每个配置当日/当月费用（amountMicros → 货币格式）与上限进度条，超限标红并显示 onExceed 动作。
5. [ ] 总控设置页：选择 modelProfile、编辑规则（按 TASK-163 内部规则 schema 的 JSON 编辑器 + 校验）、系统提示词；无“关闭总控”开关；降级时页顶显示 `BUDGET_EXCEEDED` 横幅文案。
6. [ ] 实现 `node_local_models` 6 态；总控设置页同样实现 6 态（ux-states.json 无对应 screen，按同规范实现并报缺陷）。
7. [ ] 写组件测试并运行验证命令，存证（含截图）。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 提交含测试 Key 的表单后，`localStorage`、`indexedDB`、Query 缓存序列化结果中 grep 测试 Key 0 命中（测试断言）。
- [ ] `node_local_models` 6 态以 `data-ux-state` 可断言（组件测试）。
- [ ] 用量看板在超限夹具下显示超限样式与 onExceed 文案。
- [ ] 总控设置页不存在关闭开关；降级夹具下显示横幅（测试）。
- [ ] `pnpm --filter ./apps/web build` 成功；`make guard` 通过。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-165/
pnpm --filter ./apps/web exec vitest run src/targets/node/models src/targets/node/supervisor --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-165/vitest.txt
pnpm --filter ./apps/web build | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-165/build.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-165/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-165/
- `vitest.txt`、`build.txt`、`guard.txt`
- `screenshots/`（模型列表、表单、用量看板、总控设置、降级横幅）

## 9. 允许修改
- `apps/web/src/targets/node/models/**`
- `apps/web/src/targets/node/supervisor/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-165/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-165/` 除外，见 ownership-matrix §4）
- apps/web/src/targets/node/ 下除 models/、supervisor/ 外目录
- apps/web/src/app/**、components/**、i18n/**

## 11. 依赖与阻塞
- Depends on：TASK-066, TASK-161
- Blocks：TASK-166, TASK-183
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - `/local/v1/usage` 与 `/local/v1/supervisor` 响应在契约中为无类型 `object`：若 TASK-161/163 实际返回结构与前端假设不符 → 以其实现为准并报契约缺陷；无法确定时 blocked。
  - 总控规则编辑依赖 TASK-163 定义的内部规则 schema；未提供 → 只做原始 JSON 编辑并报缺口。

## 12. 建议执行档位
sonnect　理由：本机前端表单与看板，接口已在 161/163 落地，可逆。

## 13. 升级条件
- 无。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 契约缺陷：usage、supervisor 响应无 schema；ux-states 无总控设置 screen。
- 假设：技能文件上传不在 v1（DEC-045），界面不提供。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-165/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-165.md`）
