---
id: REQ-F-011
type: requirement
title: 输出端：QQ 官方机器人
priority: MUST
status: approved
version: V0.0.4
source: DEC-054
slices: S6
---

# REQ-F-011：输出端：QQ 官方机器人

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-054
- 交付切片：S6（见 `04_planning/slices.md`）

## 2. 可验证陈述
单聊与群聊收发；主动消息受平台配额约束并按能力降级。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-011 的任务
