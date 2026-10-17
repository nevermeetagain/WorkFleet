---
id: REQ-F-006
type: requirement
title: 多中转连接
priority: MUST
status: approved
version: V0.0.4
source: DEC-048/G20
slices: S3
---

# REQ-F-006：多中转连接

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-048/G20
- 交付切片：S3（见 `04_planning/slices.md`）

## 2. 可验证陈述
一个节点可同时登录 ≥2 个中转，两边的路由、凭据、消息互不可见（隔离测试通过）。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-006 的任务
