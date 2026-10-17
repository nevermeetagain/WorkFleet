---
id: REQ-F-028
type: requirement
title: 审计
priority: MUST
status: approved
version: V0.0.4
source: DEC-047
slices: S7
---

# REQ-F-028：审计

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-047
- 交付切片：S7（见 `04_planning/slices.md`）

## 2. 可验证陈述
每条出站消息可查：发给谁、来自哪个输入端、经过哪些过滤；管理操作（改绑定、改权限、吊销设备）全部入审计。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-028 的任务
