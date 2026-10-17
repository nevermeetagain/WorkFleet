---
id: REQ-F-024
type: requirement
title: 总控：会议
priority: MUST
status: approved
version: V0.0.4
source: DEC-019
slices: S9
---

# REQ-F-024：总控：会议

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-019
- 交付切片：S9（见 `04_planning/slices.md`）

## 2. 可验证陈述
总控可组织 ≥2 个智能体开会：轮次、发言、纪要、决策四类事件可回放；主持策略“全员提交或超时”。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-024 的任务
