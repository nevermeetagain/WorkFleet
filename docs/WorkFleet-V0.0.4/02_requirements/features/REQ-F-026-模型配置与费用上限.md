---
id: REQ-F-026
type: requirement
title: 模型配置与费用上限
priority: MUST
status: approved
version: V0.0.4
source: DEC-044/G17
slices: S8
---

# REQ-F-026：模型配置与费用上限

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-044/G17
- 交付切片：S8（见 `04_planning/slices.md`）

## 2. 可验证陈述
用户可增删改模型配置（含日/月费用上限与超限动作）；Key 仅存在节点钥匙串（中转数据库与日志中 grep 不到）；超限后总控降级为规则把关并通知。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-026 的任务
