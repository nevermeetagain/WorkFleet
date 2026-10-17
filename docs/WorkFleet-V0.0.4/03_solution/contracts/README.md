---
id: WF-CONTRACTS
type: contract-index
title: 契约冻结包（六份）
status: frozen
version: V0.0.4
frozen_at: 2026-10-17
---

# 契约冻结包

唯一源在仓库 `packages/contracts/`（ADR-002）。本页只做索引、自检与需求映射，不复制内容。

## 1. 六份契约
| # | 契约 | 唯一源文件 | 必含项覆盖 |
|---|---|---|---|
| ① | API | `api/relay.openapi.json`（77 个操作）、`api/node-local.openapi.json`（31 个） | 路径、方法、请求/响应 schema、游标分页、`Idempotency-Key`、`x-auth` 鉴权、`x-permission` |
| ② | Errors | `errors/error-codes.json`（33 码） | 码、HTTP 状态、可重试、前端展示、含义 |
| ③ | Identity | `identity/permissions.json` + role/session/device schema | ID 形态（ADR-012）、角色、会话声明、设备令牌、权限矩阵、管理端越权禁止路径 |
| ④ | Resources | `resources/resources.json` | 上传/下载 URL、签名、ACL、生命周期、节点文件不上传 |
| ⑤ | Events | `protocol/`（28 种帧）+ `events/domain-events.json`（27 个事件） | 名称、载荷、触发时机、幂等键、seq/ack |
| ⑥ | UX States | `ux/ux-states.json`（37 个界面 × 6 态） | 空/加载/错误/无权限/成功/离线 |

## 2. 契约自检（规划指令 §4.4）
| 问题 | 结论 | 依据 |
|---|---|---|
| 前端能否只凭契约写出完整 API 调用层？ | 是 | OpenAPI 端点 + 实体 schema + 错误码 ui 列 + ux-states |
| 后端能否只凭契约实现接口？ | 是 | 每个端点有请求/响应 schema、权限动作、错误码清单 |
| 数据端能否只凭契约设计表结构？ | 是，且已给出 | `database/migrations/relay/0001_init.sql`、`node/0001_init.sql`（sqlite3 实测可建表） |
| 错误码是否覆盖已知失败路径？ | 是（33 码） | 每个端点 `x-errors`；协议 `error` 帧复用同一码表 |
| 管理端越权路径是否明确禁止？ | 是 | `identity/permissions.json` 的 `forbiddenPaths` 与 viewer 规则；TASK-146 逐格测试 |

## 3. 需求 → 契约映射
| 需求 | 契约位置 |
|---|---|
| REQ-F-001/002/006 | devices 端点、`protocol/frames/hello|welcome`、`relay-link.schema.json` |
| REQ-F-003 | `identity/permissions.json`、members 端点 |
| REQ-F-004/005 | projects 端点、`project.schema.json`、`device.isPrimary` |
| REQ-F-007/008 | `adapters/input-adapter-spec.schema.json`、`input-adapters.v1.json`、`/hooks/{hookId}` |
| REQ-F-009…015 | `adapters/channel-capabilities.schema.json`、`channel-kinds.v1.json`、channels 端点、qr-login |
| REQ-F-016/017 | `route.schema.json`、`routes/dry-run`、`message.replyToId`、`conversation.recipientId` |
| REQ-F-018/019 | `commands/im-commands.json`、`history/search`、`history.query` 帧 |
| REQ-F-020 | `approval.schema.json`、`approval.request|decision` 帧、`approvals/{id}/decide` |
| REQ-F-021 | `barrier.schema.json`、`barrier.submit` 帧 |
| REQ-F-022…025 | `agent.output.supervisorVerdict`、`meeting.schema.json`、node-local `/supervisor*` |
| REQ-F-026 | `model-profile.schema.json`、node-local `/model-profiles*`、`BUDGET_EXCEEDED` |
| REQ-F-027/028 | `filter-rule.schema.json`、`audit-entry.schema.json`、`delivery.filtersApplied` |
| REQ-F-029 | `twin-event.schema.json`、`twin.capture` 帧、node-local `/twin/*` |
| REQ-F-030 | `channel.health`、`channel.health_changed` 事件、push-subscriptions |
| REQ-F-033 | `emergency/*` 端点与帧、`EMERGENCY_STOPPED` |

## 4. 修订记录
- 2026-10-17 CR-001（ADR-015）：评审闭环 24 项修订 + 迁移 0002。重新冻结。67 个 schema 通过 Draft 2020-12 元校验、$ref 全部可解析、适配器表与渠道能力表按 schema 校验通过、两侧迁移 0001+0002 在 sqlite3 3.46 实测建库成功。

## 5. 冻结规则
冻结后修改契约 = 新任务（Agent-Contract）+ ADR + 档位 opus（语义变更）或 fable（推翻需求/冻结契约）；同时禁止任何实现任务并行改契约。
