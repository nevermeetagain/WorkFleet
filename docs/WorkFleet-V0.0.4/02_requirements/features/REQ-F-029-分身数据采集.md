---
id: REQ-F-029
type: requirement
title: 分身数据采集
priority: MUST
status: approved
version: V0.0.4
source: DEC-049/G21
slices: S7
---

# REQ-F-029：分身数据采集

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-049/G21
- 交付切片：S7（见 `04_planning/slices.md`）

## 2. 可验证陈述
用户本人发出的全部指令与任务时间线写入节点 `twin_event`；用户可在本机控制台查看/修改/删除/导出（JSONL）。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-029 的任务
