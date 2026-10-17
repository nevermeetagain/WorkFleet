---
id: REQ-F-008
type: requirement
title: 非 ACP 输入：Coze 与 Webhook
priority: MUST
status: approved
version: V0.0.4
source: DEC-052/055
slices: S4
---

# REQ-F-008：非 ACP 输入：Coze 与 Webhook

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-052/055
- 交付切片：S4（见 `04_planning/slices.md`）

## 2. 可验证陈述
Coze（HTTP API）可作为输入端对话；`POST 127.0.0.1:5102/hooks/{hookId}`（签名校验）的消息按绑定投递到输出端。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-008 的任务
