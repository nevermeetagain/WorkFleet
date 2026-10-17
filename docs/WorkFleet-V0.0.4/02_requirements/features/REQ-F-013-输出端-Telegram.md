---
id: REQ-F-013
type: requirement
title: 输出端：Telegram
priority: MUST
status: approved
version: V0.0.4
source: DEC-054
slices: S6
---

# REQ-F-013：输出端：Telegram

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-054
- 交付切片：S6（见 `04_planning/slices.md`）

## 2. 可验证陈述
getUpdates 长轮询收发，内联按钮审批，支持频道群发（通知模式）。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-013 的任务
