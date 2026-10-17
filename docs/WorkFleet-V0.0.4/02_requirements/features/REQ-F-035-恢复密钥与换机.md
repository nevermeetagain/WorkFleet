---
id: REQ-F-035
type: requirement
title: 恢复密钥与换机
priority: SHOULD
status: approved
version: V0.0.4
source: DEC-020/G11
slices: S10
---

# REQ-F-035：恢复密钥与换机

## 1. 基本信息
- 优先级：SHOULD
- 来源：DEC-020/G11
- 交付切片：S10（见 `04_planning/slices.md`）

## 2. 可验证陈述
导出恢复密钥后，在新电脑导入可恢复节点的加密数据。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-035 的任务
