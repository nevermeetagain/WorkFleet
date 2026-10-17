---
id: REQ-F-016
type: requirement
title: 绑定与三种模式
priority: MUST
status: approved
version: V0.0.4
source: 原始说明书；DEC-005/006
slices: S2,S5
---

# REQ-F-016：绑定与三种模式

## 1. 基本信息
- 优先级：MUST
- 来源：原始说明书；DEC-005/006
- 交付切片：S2,S5（见 `04_planning/slices.md`）

## 2. 可验证陈述
管理（多对一）、通知（一对多）、团队（多对多）三种绑定均可在控制台创建，并有 dry-run 预览显示一条样例消息会去哪；团队模式入站只到一个目标。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-016 的任务
