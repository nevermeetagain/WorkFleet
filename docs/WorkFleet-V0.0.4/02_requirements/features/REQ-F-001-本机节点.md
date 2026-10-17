---
id: REQ-F-001
type: requirement
title: 本机节点
priority: MUST
status: approved
version: V0.0.4
source: DEC-037/041
slices: S0,S10
---

# REQ-F-001：本机节点

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-037/041
- 交付切片：S0,S10（见 `04_planning/slices.md`）

## 2. 可验证陈述
在 Windows 11、macOS 14、Ubuntu 24.04 上，`workfleet-node` 安装后可开机自启、单实例运行，并在中转控制台显示“在线”。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-001 的任务
