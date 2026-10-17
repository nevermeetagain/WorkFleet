---
id: REQ-F-019
type: requirement
title: 会话与记录查询
priority: MUST
status: approved
version: V0.0.4
source: 原始说明书；DEC-004
slices: S1
---

# REQ-F-019：会话与记录查询

## 1. 基本信息
- 优先级：MUST
- 来源：原始说明书；DEC-004
- 交付切片：S1（见 `04_planning/slices.md`）

## 2. 可验证陈述
`/clear` 后 generation+1 且旧记录仍可查；按会话 display_id 或原生 resume_id 可查到两端（IM 侧与智能体侧）记录。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-019 的任务
