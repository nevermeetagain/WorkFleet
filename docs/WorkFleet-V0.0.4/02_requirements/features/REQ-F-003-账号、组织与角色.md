---
id: REQ-F-003
type: requirement
title: 账号、组织与角色
priority: MUST
status: approved
version: V0.0.4
source: DEC-047
slices: S0,S7
---

# REQ-F-003：账号、组织与角色

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-047
- 交付切片：S0,S7（见 `04_planning/slices.md`）

## 2. 可验证陈述
admin/operator/viewer 三角色的权限矩阵与 `contracts/identity/permissions.json` 一致，并由契约测试逐格验证。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-003 的任务
