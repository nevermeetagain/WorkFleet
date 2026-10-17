---
id: REQ-F-017
type: requirement
title: 回复溯源与按发送人分会话
priority: MUST
status: approved
version: V0.0.4
source: G2/G25
slices: S2,S5
---

# REQ-F-017：回复溯源与按发送人分会话

## 1. 基本信息
- 优先级：MUST
- 来源：G2/G25
- 交付切片：S2,S5（见 `04_planning/slices.md`）

## 2. 可验证陈述
在 IM 中引用某条消息回复，回复只到产生该消息的智能体会话；通知模式下两个接收人的回话进入两个独立会话。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-017 的任务
