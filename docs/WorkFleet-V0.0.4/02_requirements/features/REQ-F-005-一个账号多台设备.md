---
id: REQ-F-005
type: requirement
title: 一个账号多台设备
priority: MUST
status: approved
version: V0.0.4
source: G22
slices: S3
---

# REQ-F-005：一个账号多台设备

## 1. 基本信息
- 优先级：MUST
- 来源：G22
- 交付切片：S3（见 `04_planning/slices.md`）

## 2. 可验证陈述
同一账号登记 ≥2 台节点时，可按设备路由（`@别名` 唯一定位到设备上的智能体），目标设备离线时消息排队并提示。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-005 的任务
