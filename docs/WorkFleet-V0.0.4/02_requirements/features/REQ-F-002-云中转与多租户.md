---
id: REQ-F-002
type: requirement
title: 云中转与多租户
priority: MUST
status: approved
version: V0.0.4
source: DEC-039/048
slices: S0,S7
---

# REQ-F-002：云中转与多租户

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-039/048
- 交付切片：S0,S7（见 `04_planning/slices.md`）

## 2. 可验证陈述
两个不同组织的用户在同一中转上互相看不到对方的任何项目、渠道、消息与审计记录（跨组织请求一律返回 404 `NOT_FOUND`（不泄露存在性，ADR-015 #24））。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-002 的任务
