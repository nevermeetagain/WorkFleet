---
id: REQ-F-032
type: requirement
title: 同目录并发写保护
priority: MUST
status: approved
version: V0.0.4
source: G10/DEC-053
slices: S3
---

# REQ-F-032：同目录并发写保护

## 1. 基本信息
- 优先级：MUST
- 来源：G10/DEC-053
- 交付切片：S3（见 `04_planning/slices.md`）

## 2. 可验证陈述
同一工作目录同一时刻只允许一个写入型智能体持有租约；第二个写入请求被拒或自动分配 git worktree。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-032 的任务
