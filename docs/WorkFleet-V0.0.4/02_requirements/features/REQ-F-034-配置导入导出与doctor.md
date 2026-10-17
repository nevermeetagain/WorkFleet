---
id: REQ-F-034
type: requirement
title: 配置导入导出与 doctor
priority: SHOULD
status: approved
version: V0.0.4
source: DEC-014
slices: S10
---

# REQ-F-034：配置导入导出与 doctor

## 1. 基本信息
- 优先级：SHOULD
- 来源：DEC-014
- 交付切片：S10（见 `04_planning/slices.md`）

## 2. 可验证陈述
业务配置可导出/导入 YAML（不含密钥）；`workfleet doctor` 检查端口、钥匙串、中转连通、智能体可执行文件。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-034 的任务
