---
id: REQ-F-022
type: requirement
title: 总控：把关分级
priority: MUST
status: approved
version: V0.0.4
source: DEC-018/043
slices: S8
---

# REQ-F-022：总控：把关分级

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-018/043
- 交付切片：S8（见 `04_planning/slices.md`）

## 2. 可验证陈述
总控模式下每条智能体输出都经总控分级为 直回/合并/上报/丢弃 之一并记录理由；不可关闭。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-022 的任务
