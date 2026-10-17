---
id: REQ-F-030
type: requirement
title: 通知分级与渠道健康
priority: MUST
status: approved
version: V0.0.4
source: DEC-023/G7
slices: S6
---

# REQ-F-030：通知分级与渠道健康

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-023/G7
- 交付切片：S6（见 `04_planning/slices.md`）

## 2. 可验证陈述
p0–p3 四级；凭据失效、额度将尽、长连接断开在 60 秒内产生 p0 告警并走备用渠道。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-030 的任务
