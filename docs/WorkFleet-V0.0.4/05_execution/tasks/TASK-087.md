# TASK-087：S4 输入冒烟矩阵与证据汇总

```yaml
id: TASK-087
slice: S4
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-QA
tier: haiku
size: 小
title: "S4 输入冒烟矩阵与证据汇总"
dependsOn: ["081", "082", "083", "084", "085", "086"]
blocks: ["210"]
reqs: "REQ-F-007/008"
allowedPaths: ["docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-087/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S4（可演示：13 个 ACP 智能体 + Coze + Webhook 冒烟矩阵全部有结论）
- 来源需求：REQ-F-007/008
- 来源方案：ADR-007、ADR-011；DEC-055；REQ-F-007/008 验收口径

## 2. 目标
汇总 S4 输入冒烟矩阵：13 个 ACP 智能体 + Coze + Webhook 共 15 行，每行给出版本、实测启动参数、loadSession、夹具回放结果、真机冒烟结论与证据链接，并列出需 Agent-Contract 同步的差异。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/04_planning/slices.md`（S4：冒烟矩阵全部有结论）
  - `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-022/`、`EVD-081/`…`EVD-086/`（上游证据）
  - `docs/WorkFleet-V0.0.2/30-协议与端点/02-输入端接入矩阵.md` §7
- 契约：
  - `packages/contracts/adapters/input-adapters.v1.json`（15 行 adapterId 为矩阵主键）
  - `packages/contracts/adapters/input-adapter-spec.schema.json`（对比字段：launch、supportsLoadSession、experimental、docsUrl）
- 前置任务：TASK-081, TASK-082, TASK-083, TASK-084, TASK-085, TASK-086
- 前置状态：TASK-081…086 均为 done 或 blocked（blocked 行以原因入矩阵）；EVD-022 已存在

## 4. 输出
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-087/smoke-matrix.md`：15 行矩阵
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-087/smoke-matrix.json`：同内容机器可读
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-087/contract-sync.md`：需同步 input-adapters.v1.json 的差异清单（汇总各卡 followups.md）
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-087/check_matrix.py`：矩阵完整性检查脚本
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-087/`（本任务的证据目录即其产物目录）

## 5. Execution Steps
1. [ ] 从 input-adapters.v1.json 取 15 个 adapterId 作为矩阵行。
2. [ ] 逐个读取 EVD-022（claude-code/codex/cursor）、EVD-081（group A）、EVD-082（group B）、EVD-083（openclaw）、EVD-084（zcode）、EVD-085（coze）、EVD-086（webhook）的结论。
3. [ ] 每行填写：版本、OS、实测 launch、supportsLoadSession（契约值 → 实测值）、夹具回放 PASS/FAIL、真机冒烟 PASS/FAIL/UNKNOWN、失败原因、证据链接。
4. [ ] 实验项（github-copilot、zcode）FAIL 时必须有原因；非实验项 FAIL/UNKNOWN 标红并列入 S4 未完成项。
5. [ ] 汇总各卡 followups.md 为 contract-sync.md（字段、契约值、实测值、来源证据）。
6. [ ] 编写 check_matrix.py：校验 15 行齐全、每行必填列非空、链接指向存在的证据目录；运行并保存输出。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] smoke-matrix.json 恰好 15 行，adapterId 与 input-adapters.v1.json 完全一致（脚本断言）
- [ ] 每行“真机冒烟”列非空；FAIL/UNKNOWN 行均有原因
- [ ] 每行证据链接指向存在的 EVD 目录
- [ ] contract-sync.md 列出全部契约值与实测值不一致的字段
- [ ] 越界检查只输出 SCOPE OK

## 7. 验证命令
```bash
python3 docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-087/check_matrix.py \
  --contracts packages/contracts/adapters/input-adapters.v1.json \
  --matrix docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-087/smoke-matrix.json \
  | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-087/check-output.txt
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-087/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-087/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-087/
- `smoke-matrix.md` / `smoke-matrix.json`
- `contract-sync.md`
- `check_matrix.py`、`check-output.txt`

## 9. 允许修改
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-087/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-087/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- 其他 EVD 目录（只读引用，不修改上游证据）
- apps/**、packages/**（含 contracts）

## 11. 依赖与阻塞
- Depends on：TASK-081, TASK-082, TASK-083, TASK-084, TASK-085, TASK-086
- Blocks：TASK-210
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 任一上游卡既不是 done 也没有 blocked 原因（矩阵行无法给出结论）
  - 上游证据缺少版本或冒烟结论字段

## 12. 建议执行档位
haiku　理由：纯汇总与填表，不改任何领域规则，haiku 足够。

## 13. 升级条件
- 需要判断某个 FAIL 是否可接受（非实验项）→ 升 sonnect/opus 由规划裁决
- 上游证据互相矛盾 → 升 opus

## 14. 预估规模
小(<0.5d)　是否小于 2 小时：否

## 15. 风险与假设
- U-05（NON_BLOCKING）：矩阵即 U-05 的实测关闭依据；未实测行保持“待实测”，不得推断填写。
- U-06（NON_BLOCKING）：zcode 行允许 FAIL。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - Agent-Contract：依据 contract-sync.md 统一同步 input-adapters.v1.json（单独任务 + ADR）

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-087/
- 验证者结论：
- 遗留问题 / 跟进项编号：
