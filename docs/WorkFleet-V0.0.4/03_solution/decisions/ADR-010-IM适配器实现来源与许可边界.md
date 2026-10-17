---
id: ADR-010
type: adr
title: IM 适配器实现来源与许可边界
status: accepted
version: V0.0.4
created: 2026-10-17
decider: 规划 Agent（opus 档）；用户可推翻
---

# ADR-010：IM 适配器实现来源与许可边界

## 1. Context
DEC-009/033：Apache-2.0 仓库，AGPL/EULA 代码不拷贝。

## 2. Problem
需要一个可执行、可验证、可逆的选择，供并行开发 CLI 共同遵守。

## 3. Options
每个渠道：官方 SDK > MIT/Apache 社区库 > 自写 HTTP（clean-room）

## 4. Decision
飞书/Lark：官方 Node SDK 长连接；钉钉：官方 Stream SDK；QQ：官方开放平台 WebSocket（自写客户端）；Telegram：Bot API getUpdates（自写或 MIT 库）；Discord：Gateway（Apache-2.0 库）；微信 ClawBot：iLink HTTP 长轮询 clean-room（只读公开文档与参考项目设计，不拷贝代码）。

## 5. Rationale
各库许可在 TASK 中逐个核实并写入 THIRD_PARTY_NOTICES。

## 6. Consequences
### Positive
+ 合规。
### Negative
− 部分渠道需自写。
### Risks
任一库许可不兼容 → 改自写，不阻塞他渠道。

## 7. Status
accepted（2026-10-17）。推翻需新 ADR，并把本文改为 superseded。

## 8. Related
DEC-009/033；DESIGN-008
