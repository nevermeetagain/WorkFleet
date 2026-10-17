---
id: REQ-NF-004
type: requirement
title: 安全
priority: MUST
status: approved
version: V0.0.4
source: DEC-030/044、G8
---

# REQ-NF-004：安全

## 可验证陈述
中转只开 443；节点端口只绑 127.0.0.1；IM 发送者默认未授权；入站文本按不可信处理；模型 Key 不出节点；gitleaks 门禁。

## 验证方式
见 `06_validation/validation-plan.md` 与 `04_planning/baseline-metrics.md`。
