---
id: REQ-F-018
type: requirement
title: IM 与控制台指令
priority: MUST
status: approved
version: V0.0.4
source: DEC-011/G9
slices: S1,S2
---

# REQ-F-018：IM 与控制台指令

## 1. 基本信息
- 优先级：MUST
- 来源：DEC-011/G9
- 交付切片：S1,S2（见 `04_planning/slices.md`）

## 2. 可验证陈述
`/clear /list /use /@别名 /stop /stop all /status /history /bind /help` 在所有渠道与 Web 行为一致（以 `contracts/commands/im-commands.json` 为准）。

## 3. 关联
- 契约：`packages/contracts/`（见 `03_solution/contracts/README.md` 的需求→契约映射）
- 设计：`03_solution/design/`（见 architecture §8）
- 任务：`05_execution/task-index.md` 中“来源需求”列为 REQ-F-018 的任务
