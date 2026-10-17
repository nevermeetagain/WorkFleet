---
id: WF-ACCEPTANCE-README
type: validation
title: 验收记录（VAL）目录规则与模板
status: active
version: V0.0.4
created: 2026-10-17
sources: [docs/项目完整文档体系.txt §25/§38, 06_validation/validation-plan.md, 00_governance/document-standard.md §4–5]
---

# 验收记录（VAL）

## 1. 命名与编号
- 一个任务一份验收记录：`VAL-<任务号>.md`，**编号与被验任务相同**（`TASK-013` → `VAL-013.md`），对应证据目录 `../evidence/EVD-013/`（文档体系 §38 示例 TASK-142 → VAL-142 → EVD-142）。
- 同一任务被重新验收：在同一文件内追加“第 N 轮”小节，不新建文件、不覆盖旧轮次（历史不覆盖，文档体系 §3.6）。
- 里程碑验收用该切片 E2E 任务的 VAL（如 M0 = VAL-013，v1 = VAL-210）。
- 只有**独立验证者**可以写 VAL 的结论字段（`validation-plan.md §1`）。

## 2. 模板
复制以下内容新建 `VAL-XXX.md`：

````markdown
---
id: VAL-XXX
type: validation
title: TASK-XXX 验收记录
status: active
version: V0.0.4
created: YYYY-MM-DD
task: TASK-XXX
requirements: [REQ-F-xxx]
solution: [SOL-001, ADR-xxx]
verifier: <独立验证者标识（不得是该任务执行者）>
---

# VAL-XXX：TASK-XXX 验收记录

## 1. 基本信息
- Task：TASK-XXX（`05_execution/tasks/TASK-XXX.md`）
- Requirement：REQ-…
- Solution / Decision：SOL-… / ADR-…
- 被验提交：<commit SHA>（分支 <branch>，PR <链接或编号>）
- 验证日期（CST）：YYYY-MM-DD HH:MM
- 验证环境：<OS / Node 版本 / 中转与节点位置>

## 2. Verification Target
<验证什么：引用任务卡第 2 节目标>

## 3. Verification Method
<复制任务卡第 7 节验证命令；补充人工步骤（如真机）>

## 4. 逐条结果
| # | 验收条目（逐字抄任务卡第 6 节） | 预期 | 实际 | 结论 | 证据 |
|---|---|---|---|---|---|
| 1 | … | … | … | PASS / FAIL / UNKNOWN | EVD-XXX/… |

## 5. Done 七项检查（current-plan.md §11）
| 条件 | 结论 | 证据 |
|---|---|---|
| 所有权内 diff 符合任务 | | |
| 验收条目逐条有结果 | | |
| 自动测试或脚本可复现 | | |
| evidence 能让一周后的人复现 | | |
| make guard 通过 | | |
| 无新增同类错误记录 | | |
| 未修改冻结契约 | | |

## 6. Result
**PASS / FAIL / UNKNOWN**（只能三选一）

## 7. Issues
- <发现的问题；UNKNOWN 必须写缺什么、谁能补>

## 8. Conclusion
<一句话结论>

## 9. 轮次记录
| 轮次 | 日期 | 提交 | 结论 | 验证者 |
|---|---|---|---|---|
| 1 | | | | |
````

## 3. 规则
- 结论只依据 EVD 中可复现的材料；执行者的口头说明、PR 描述不构成证据。
- 任一条目 FAIL → 总结论 FAIL；无 FAIL 但有 UNKNOWN → 总结论 UNKNOWN；全部 PASS 且 Done 七项全部满足 → PASS。
- 同一任务连续 2 次 FAIL → 触发熔断（`04_planning/cost-budget.md §4`），在 Issues 中注明。
