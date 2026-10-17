---
id: REQ-F-004
type: requirement
title: 项目一级对象与主/子项目
priority: MUST
status: approved
version: V0.0.4
source: G23
slices: S3
---

# REQ-F-004：项目一级对象与主/子项目

## 1. 基本信息
- 优先级：MUST
- 来源：G23
- 交付切片：S3（见 `04_planning/slices.md`）

## 2. 可验证陈述
用户可建主项目与子项目（深度 ≤3），会话、绑定与智能体都必须归属一个项目，跨项目视图可按树汇总未读与状态。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-004 的任务
