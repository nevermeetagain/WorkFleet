---
id: WF-CONSTRAINTS
type: constraints
title: 技术/业务约束汇总
status: approved
version: V0.0.4
created: 2026-10-17
---

# 约束汇总
唯一源为 `02_requirements/constraints/REQ-C-001…009`；本页只索引。

| 约束 | 对设计的直接影响 |
|---|---|
| REQ-C-001 TS/Node | 全部应用与包同语言；契约生成 TS |
| REQ-C-002 Apache-2.0 | 依赖许可核查；clean-room 边界（DESIGN-008） |
| REQ-C-003 端口段 / 443 | 端口分配见 architecture §3 |
| REQ-C-004 一个 Bot 一个消费者 | `channels.bot_identity_hash` 全局唯一索引；BOT_IDENTITY_CONFLICT |
| REQ-C-005 香港 / Ubuntu | 跨境链路 → ADR-005 续传设计 |
| REQ-C-006 模型只在本机 | 模型配置只在 node-local API；中转 schema 无 Key 字段 |
| REQ-C-007 仓库治理 | 分支 + PR、目录守卫、版本文档目录 |
| REQ-C-008 微信限额 | 额度预算器、续期提示、能力 `proactiveQuota` |
| REQ-C-009 ZCode 实验 | 适配器标 experimental，失败不阻塞验收 |
