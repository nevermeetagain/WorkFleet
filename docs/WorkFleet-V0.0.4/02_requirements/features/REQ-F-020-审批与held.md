---
id: REQ-F-020
type: requirement
title: 审批与 held
priority: MUST
status: approved
version: V0.0.4
source: DEC-011/012
slices: S2
---

# REQ-F-020：审批与 held

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-011/012
- 交付切片：S2（见 `04_planning/slices.md`）

## 2. 可验证陈述
智能体权限请求在 IM/Web 以按钮或 `Y{n}/N{n}` 审批；超时默认拒绝；待审批期间发往该智能体的新消息进入 held，审批后按序投递。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-020 的任务
