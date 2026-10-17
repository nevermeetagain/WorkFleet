---
id: REQ-F-023
type: requirement
title: 总控：随时对话与任务分派
priority: MUST
status: approved
version: V0.0.4
source: 原始说明书；DEC-043
slices: S8
---

# REQ-F-023：总控：随时对话与任务分派

## 1. 基本信息
- 优先级：MUST
- 来源：原始说明书；DEC-043
- 交付切片：S8（见 `04_planning/slices.md`）

## 2. 可验证陈述
用户与总控对话时，正在执行的任务不暂停、不丢消息；总控可把任务分派给 1..N 个智能体。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-023 的任务
