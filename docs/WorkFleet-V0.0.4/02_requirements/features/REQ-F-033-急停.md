---
id: REQ-F-033
type: requirement
title: 急停
priority: MUST
status: approved
version: V0.0.4
source: G9
slices: S10
---

# REQ-F-033：急停

## 1. 基本信息
- 优先级：MUST
- 来源：G9
- 交付切片：S10（见 `04_planning/slices.md`）

## 2. 可验证陈述
`/stop all` 在 5 秒内冻结该账号所有智能体与出站；控制台可恢复。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-033 的任务
