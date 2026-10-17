---
id: REQ-F-027
type: requirement
title: 接收人级权限与脱敏
priority: MUST
status: approved
version: V0.0.4
source: DEC-047/G3
slices: S7
---

# REQ-F-027：接收人级权限与脱敏

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-047/G3
- 交付切片：S7（见 `04_planning/slices.md`）

## 2. 可验证陈述
同一条汇总发给老板与数据部时，按“接收人 × 业务线 × 字段”规则得到不同的可见字段；脱敏规则有单测。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-027 的任务
