---
id: ADR-014
type: adr
title: PWA 与 Web Push
status: accepted
version: V0.0.4
created: 2026-10-17
decider: 规划 Agent（opus 档）；用户可推翻
---

# ADR-014：PWA 与 Web Push

## 1. Context
DEC-057：不接 IM 也要在手机收到审批/完成。

## 2. Problem
需要一个可执行、可验证、可逆的选择，供并行开发 CLI 共同遵守。

## 3. Options
A Web Push（VAPID）；B 自建 App；C 仅邮件

## 4. Decision
选 A。

## 5. Rationale
零安装成本；iOS 需添加到主屏幕且 iOS 16.4+ 才支持 Web Push（部分确认，TASK 实测）。

## 6. Consequences
### Positive
+ 不依赖 IM。
### Negative
− iOS 限制。
### Risks
推送失败 → 回退到用户配置的 IM 或邮件（v2）。

## 7. Status
accepted（2026-10-17）。推翻需新 ADR，并把本文改为 superseded。

## 8. Related
DESIGN-017
