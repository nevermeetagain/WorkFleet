---
id: REQ-F-031
type: requirement
title: Bot 唯一消费者与画像向导
priority: MUST
status: approved
version: V0.0.4
source: DEC-034/G13/G14
slices: S10
---

# REQ-F-031：Bot 唯一消费者与画像向导

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-034/G13/G14
- 交付切片：S10（见 `04_planning/slices.md`）

## 2. 可验证陈述
向导按画像 P1/P2 生成默认配置；检测到同一 Bot 身份被他处消费（消息丢失/被顶掉）时告警。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-031 的任务
