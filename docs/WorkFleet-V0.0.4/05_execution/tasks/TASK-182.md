# TASK-182：导入任务清单（task-template 解析）与依赖顺序分派

```yaml
id: TASK-182
slice: S9
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Node
tier: sonnect
size: 中
title: "导入任务清单（task-template 解析）与依赖顺序分派"
dependsOn: ["164"]
blocks: ["184"]
reqs: "REQ-F-025"
allowedPaths: ["apps/node/src/modules/supervisor/application/import/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S9
- 来源需求：REQ-F-025
- 来源方案：REQ-F-025（G24：读取 task-template 格式任务卡直接分派，跳过会议拆解）；DEC-043

## 2. 目标
总控读取指定目录下符合 `05_execution/task-template.md` 格式的任务卡，校验 16 节与 yaml 头，按“依赖与阻塞”构建 DAG（检测环），支持 dryRun 预览，并按依赖顺序分派给映射的智能体。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/05_execution/task-template.md（解析格式的唯一依据）
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-025）
  - docs/WorkFleet-V0.0.4/04_planning/dag.md（DAG/环检测口径）
- 契约：
  - packages/contracts/api/node-local.openapi.json：`POST /local/v1/supervisor/import-tasks`（body `{dir, dryRun?}`；响应为无类型 object）
  - packages/contracts/schemas/common/ids.schema.json（`taskId`）；errors/error-codes.json：`VALIDATION_FAILED`、`AGENT_UNAVAILABLE`
  - database/migrations/node/0001_init.sql：`supervisor_tasks`（source `import`、depends_on JSON、state）
- 前置任务：TASK-164
- 前置状态：TASK-164 已合并（dispatch 用例可用）。

## 4. 输出
- apps/node/src/modules/supervisor/application/import/parser.ts（Markdown → TaskCard：yaml 块字段、16 节标题、Depends on、允许/禁止修改）
- apps/node/src/modules/supervisor/application/import/plan.ts（DAG、环检测、拓扑序、owner→智能体映射）
- apps/node/src/modules/supervisor/application/import/import-tasks.ts（dryRun 预览 / 正式导入 → dispatch）
- apps/node/src/modules/supervisor/application/import/__tests__/ 与 `__fixtures__/cards/`（合法、缺节、环、未映射 owner 四组样例）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-182/`（见 §8）

## 5. Execution Steps
1. [ ] 解析器：只读取 `dir` 下匹配 `TASK-*.md` 的文件（不递归、单文件 ≤1 MiB、拒绝符号链接与 `..` 路径）；提取 ```yaml 块的 id/slice/status/owner/tier/size，校验 `## 1.`…`## 16.` 齐全，提取 §11 “Depends on”。
2. [ ] 校验：缺节/yaml 字段缺失/id 与文件名不一致 → 该卡进入 errors 列表（不中断其他卡）；`status` 为 done/cancelled 的卡跳过。
3. [ ] 计划：构建 DAG（依赖指向目录外且不是 done 的任务视为未满足），环检测失败 → 整体 `VALIDATION_FAILED` 并列出环；输出拓扑层级。
4. [ ] owner→智能体映射：契约请求体只有 `dir`/`dryRun`，映射来源默认读取总控设置中的映射表（`kv_settings` 键 `supervisor.import.ownerMap`，推断）；未映射的卡标为 `unassigned` 并在结果中上报，不由模型臆测分派对象。
5. [ ] dryRun=true：返回 `{cards, errors, layers, unassigned}` 不写库；dryRun=false：写入 `supervisor_tasks(source=import, depends_on)` 并调用 dispatch，前置完成后才投递后继。
6. [ ] 写测试：合法 5 卡 3 层按序分派；含环被拒；缺节卡被列入 errors；未映射 owner 进入 unassigned；路径穿越被拒。
7. [ ] 运行验证命令并存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 合法样例：5 张卡按拓扑层顺序分派，后继卡只在前置 done 后投递（FakeAgent 接收时间断言）。
- [ ] 环样例返回 `VALIDATION_FAILED` 且列出环上的任务 id；不写任何 supervisor_tasks。
- [ ] 缺节/字段缺失卡出现在 errors 中，其余卡正常导入。
- [ ] dryRun 不产生任何数据库写入（测试前后行数相同）。
- [ ] `dir` 含 `..`、符号链接或非 TASK-*.md 文件被忽略/拒绝（测试）。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-182/
WF_NET_DISABLED=1 pnpm --filter ./apps/node exec vitest run src/modules/supervisor/application/import --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-182/vitest.txt
pnpm --filter ./apps/node exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-182/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-182/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-182/
- `vitest.txt`、`tsc.txt`、`guard.txt`
- `dry-run-sample.json`（对 `__fixtures__/cards/valid` 的预览输出）
- `self-import.txt`（对本仓库 `docs/WorkFleet-V0.0.4/05_execution/tasks/` 的 dryRun 结果：解析成功数、errors）

## 9. 允许修改
- `apps/node/src/modules/supervisor/application/import/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-182/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-182/` 除外，见 ownership-matrix §4）
- apps/node/src/modules/supervisor/ 下除 application/import 外文件（`/local/v1/supervisor/import-tasks` 路由挂载在 interfaces，见阻塞条件）

## 11. 依赖与阻塞
- Depends on：TASK-164
- Blocks：TASK-184
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 接口层 `supervisor/interfaces/http` 不在本卡允许路径：若 TASK-163 未把 `import-tasks` 端点委托给 `application/import` 的用例 → blocked，报主 Agent。
  - owner→智能体映射无契约来源：若主 Agent 不接受 kv_settings 方案 → 需契约增加请求字段（ADR + 券）。

## 12. 建议执行档位
sonnect　理由：格式由 task-template 固定，解析 + 拓扑排序 + 调用现有 dispatch，确定性强。

## 13. 升级条件
- 需要用模型推断分派对象或拆解任务（越出“跳过会议拆解”）→ opus 设计审。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：导入时依赖于目录外的任务，若其状态未知则视为未满足（保守）。
- 风险：task-template 若后续改版（节号变化）解析器需同步 → 解析器按“## N.”编号识别，节名变化只告警。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-182/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-182.md`）
