---
id: REQ-NF-003
type: requirement
title: 可靠性
priority: MUST
status: approved
version: V0.0.4
source: ADR-005
---

# REQ-NF-003：可靠性

## 可验证陈述
所有跨进程消息至少一次投递 + 幂等键去重；中转重启或断线 10 分钟内恢复后不丢消息、不重复外发。

## 验证方式
见 `06_validation/validation-plan.md` 与 `04_planning/baseline-metrics.md`。
