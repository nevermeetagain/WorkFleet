---
id: REQ-F-021
type: requirement
title: 汇总屏障
priority: MUST
status: approved
version: V0.0.4
source: G1/DEC-053
slices: S5
---

# REQ-F-021：汇总屏障

## 1. 基本信息
- 优先级：MUST
- 来源：G1/DEC-053
- 交付切片：S5（见 `04_planning/slices.md`）

## 2. 可验证陈述
配置 N 个来源的汇总任务，在全部提交或超时后只发出一条汇总；超时时标注缺失来源。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-021 的任务
