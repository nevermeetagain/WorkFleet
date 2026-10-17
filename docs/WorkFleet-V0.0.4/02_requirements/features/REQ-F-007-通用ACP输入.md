---
id: REQ-F-007
type: requirement
title: 通用 ACP 输入
priority: MUST
status: approved
version: V0.0.4
source: DEC-007/055
slices: S1,S4
---

# REQ-F-007：通用 ACP 输入

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-007/055
- 交付切片：S1,S4（见 `04_planning/slices.md`）

## 2. 可验证陈述
按 `InputAdapterSpec` 表接入 ACP 智能体；DEC-055 实测清单中每一个都有通过的录制回放夹具与一次真机冒烟记录（实验项允许标注失败原因）。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-007 的任务
