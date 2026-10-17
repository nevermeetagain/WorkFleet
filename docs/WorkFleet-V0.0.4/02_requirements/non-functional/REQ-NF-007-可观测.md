---
id: REQ-NF-007
type: requirement
title: 可观测
priority: MUST
status: approved
version: V0.0.4
source: DEC-024
---

# REQ-NF-007：可观测

## 可验证陈述
所有日志带 trace_id 贯穿 web→relay→node→agent；/metrics（Prometheus 文本）；死信可在控制台查看与重放。

## 验证方式
见 `06_validation/validation-plan.md` 与 `04_planning/baseline-metrics.md`。
