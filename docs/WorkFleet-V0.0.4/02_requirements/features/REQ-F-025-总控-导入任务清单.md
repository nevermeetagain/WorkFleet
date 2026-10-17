---
id: REQ-F-025
type: requirement
title: 总控：导入任务清单
priority: MUST
status: approved
version: V0.0.4
source: G24
slices: S9
---

# REQ-F-025：总控：导入任务清单

## 1. 基本信息
- 优先级：MUST
- 来源：G24
- 交付切片：S9（见 `04_planning/slices.md`）

## 2. 可验证陈述
总控可读取指定目录下符合 `task-template.md` 格式的任务卡并直接分派，跳过会议拆解。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-025 的任务
