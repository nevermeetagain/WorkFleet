---
id: REQ-F-010
type: requirement
title: 输出端：飞书/Lark
priority: MUST
status: approved
version: V0.0.4
source: DEC-035/G16
slices: S5
---

# REQ-F-010：输出端：飞书/Lark

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-035/G16
- 交付切片：S5（见 `04_planning/slices.md`）

## 2. 可验证陈述
同一适配器按配置连接 feishu.cn 或 larksuite.com，长连接收消息、卡片按钮审批、卡片流式更新。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-010 的任务
