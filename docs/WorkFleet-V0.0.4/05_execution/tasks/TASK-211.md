# TASK-211：文档同步：用户指南、project-map、task-index 状态

```yaml
id: TASK-211
slice: S10
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Docs
tier: haiku
size: 小
title: "文档同步：用户指南、project-map、task-index 状态"
dependsOn: ["210"]
blocks: []
reqs: "REQ-C-007"
allowedPaths: ["docs/**（不含 06_validation/evidence）"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S10
- 来源需求：REQ-C-007
- 来源方案：REQ-C-007（仓库治理：目录与文档按规范）；document-standard（文档体系）

## 2. 目标
在 v1 验收后同步文档：用户指南（安装、配对、Web 对话、IM 绑定、总控、急停、doctor/恢复）、project-map（实际目录结构）、task-index 中 84 张任务的状态与验证结论，且不改动任何证据目录与需求/决策语义。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/00_governance/document-standard.md
  - docs/WorkFleet-V0.0.4/05_execution/task-index.md
  - docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-*.md（只读）
  - docs/项目完整目录结构.txt（project-map 规范）
- 契约：
  - （文档任务，不涉及运行时契约；只读引用 packages/contracts/commands/im-commands.json 与 errors/error-codes.json 写用户指南的指令与错误说明）
- 前置任务：TASK-210
- 前置状态：TASK-210 已完成并给出 VAL-210 结论。

## 4. 输出
- docs/WorkFleet-V0.0.4/07_release/user-guide.md（新建，type: release 或 knowledge，按 document-standard 取值）
- docs/WorkFleet-V0.0.4/00_governance/project-map.md（新建/更新，type: project-map）
- docs/WorkFleet-V0.0.4/05_execution/task-index.md（只改“状态”列）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-211/`（见 §8）

## 5. Execution Steps
1. [ ] 读 document-standard 的 type/命名/状态规则；确认 user-guide 与 project-map 的 front matter 取值。
2. [ ] 生成 project-map：以实际仓库 `find apps packages tests infra scripts -maxdepth 4 -type d` 输出为准，标注每个目录的所有者（ownership-matrix）。
3. [ ] 写用户指南：按 Web 默认渠道主路径组织；指令表直接引用 im-commands.json（不改写语义）；错误码表引用 error-codes.json 的 ui 文案；标注实验项（ZCode、Copilot）与 iOS 推送限制（以 EVD-204 结论为准）。
4. [ ] 更新 task-index 状态列：仅当 `06_validation/acceptance/VAL-<id>.md` 结论为 PASS 时标 done；FAIL→in_progress 或 blocked（按 VAL 说明）；UNKNOWN→blocked；不改其他列。
5. [ ] 自检：运行 §7 的内联核对脚本（task-index 84 行与 tasks.v1.json 的标题/所有者/档位一致、状态与 VAL 结论一致）与链接检查。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] task-index 每行状态与对应 VAL 结论一致（脚本核对 84/84）。
- [ ] task-index 除状态列外与 tasks.v1.json 一致（脚本 diff 为空）。
- [ ] user-guide 中的指令表与 im-commands.json 逐条一致（脚本比对 syntax 列）。
- [ ] 所有新增/修改文档的内部链接可解析（链接检查 0 失败）；`06_validation/evidence/**` 无任何改动（git diff 为空）。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-211/
python3 - <<'PY' | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-211/index-check.txt
import json, re, pathlib
root = pathlib.Path("docs/WorkFleet-V0.0.4")
tasks = {t["id"]: t for t in json.load(open(root / "05_execution/tasks.v1.json"))}
rows = [l for l in (root / "05_execution/task-index.md").read_text().splitlines() if l.startswith("| [TASK-")]
bad = 0
for l in rows:
    c = [x.strip() for x in l.strip("|").split("|")]
    tid = re.search(r"TASK-(\d+)", c[0]).group(1)
    t = tasks[tid]
    val = root / f"06_validation/acceptance/VAL-{tid}.md"
    verdict = next((v for v in ("PASS", "FAIL", "UNKNOWN") if val.exists() and v in val.read_text()), None)
    expect = {"PASS": "done", "FAIL": None, "UNKNOWN": "blocked", None: None}[verdict]
    if c[2] != t["title"] or c[4] != t["owner"] or c[5] != t["tier"]:
        bad += 1; print("FIELD MISMATCH", tid)
    if expect and c[-1] != expect:
        bad += 1; print("STATUS MISMATCH", tid, c[-1], "expect", expect)
print("rows", len(rows), "tasks", len(tasks), "mismatches", bad)
PY
git diff --stat -- docs/WorkFleet-V0.0.4/06_validation/evidence | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-211/evidence-untouched.txt
npx --yes markdown-link-check -q docs/WorkFleet-V0.0.4/07_release/user-guide.md docs/WorkFleet-V0.0.4/00_governance/project-map.md docs/WorkFleet-V0.0.4/05_execution/task-index.md | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-211/links.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-211/
- `index-check.txt`（task-index 与 VAL/tasks.v1.json 核对输出）
- `evidence-untouched.txt`、`links.txt`

## 9. 允许修改
- `docs/**（不含 06_validation/evidence）`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-211/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-211/` 除外，见 ownership-matrix §4）
- docs/WorkFleet-V0.0.4/06_validation/evidence/**（除本卡 EVD-211 外）
- docs/**/02_requirements/**、03_solution/decisions/**、docs/WorkFleet-V0.0.3/**（只读，不改需求/决策语义）
- apps/**、packages/**、scripts/**（检查脚本以内联方式运行，不入库；scripts/docs 不在本卡路径）

## 11. 依赖与阻塞
- Depends on：TASK-210
- Blocks：—
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - VAL-210 缺失或结论为 UNKNOWN 的任务超过一半：只更新已有结论的行，其余保持原状态并在完成记录说明。
  - 允许路径写作 `docs/**（不含 06_validation/evidence）`，而 ownership §4 又允许各任务写自己的 EVD 目录：本卡 EVD-211 按 §4 例外处理；若主 Agent 认为冲突，证据改放完成记录内。

## 12. 建议执行档位
haiku　理由：格式化与索引更新，不改领域规则（cost-budget：haiku 职责）。

## 13. 升级条件
- 需要改写需求、ADR 或解释验证结论 → sonnect/opus（haiku 禁止改领域规则）。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
小　是否小于 2 小时：否

## 15. 风险与假设
- 假设：用户指南放 07_release（推断，document-standard 未列 user-guide 的固定位置）。
- 风险：验证命令中的 `markdown-link-check` 需网络安装；断网时改用离线链接检查。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-211/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-211.md`）
