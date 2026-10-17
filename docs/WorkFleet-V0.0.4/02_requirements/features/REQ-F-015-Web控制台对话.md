---
id: REQ-F-015
type: requirement
title: Web 控制台对话（默认渠道）
priority: MUST
status: approved
version: V0.0.4
source: DEC-056/057
slices: S0,S1,S10
---

# REQ-F-015：Web 控制台对话（默认渠道）

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-056/057
- 交付切片：S0,S1,S10（见 `04_planning/slices.md`）

## 2. 可验证陈述
不配置任何 IM 时，用户可在 Web 完成：注册→配对节点→与智能体对话→审批→查历史；PWA 安装后能收到 Web Push。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-015 的任务
