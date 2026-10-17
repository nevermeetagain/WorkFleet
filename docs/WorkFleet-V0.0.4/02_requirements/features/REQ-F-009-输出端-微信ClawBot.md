---
id: REQ-F-009
type: requirement
title: 输出端：微信 ClawBot
priority: MUST
status: approved
version: V0.0.4
source: DEC-034/023
slices: S2
---

# REQ-F-009：输出端：微信 ClawBot

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-034/023
- 交付切片：S2（见 `04_planning/slices.md`）

## 2. 可验证陈述
控制台扫码一次完成绑定；授权失效时 p0 告警；主动消息受额度预算器约束并在剩余 ≤3 条时提示续期。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-009 的任务
