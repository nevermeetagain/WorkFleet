---
id: REQ-NF-002
type: requirement
title: 并发与资源
priority: MUST
status: approved
version: V0.0.4
source: DEC-021；场景 1
---

# REQ-NF-002：并发与资源

## 可验证陈述
单节点 ≥ 8 个并发智能体会话；空闲会话 15 分钟回收；节点控制面常驻内存 ≤ 200 MB（不含子进程）。

## 验证方式
见 `06_validation/validation-plan.md` 与 `04_planning/baseline-metrics.md`。
