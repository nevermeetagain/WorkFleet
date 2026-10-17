---
id: DESIGN-004
type: design
title: 数据详细设计（relay.db / node.db 的 0001 迁移逐表说明与迁移编排）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - "database/migrations/relay/0001_init.sql"
  - "database/migrations/node/0001_init.sql"
  - "ADR-003"
  - "ADR-012"
  - "DEC-004"
  - "DEC-008"
  - "DEC-028"
  - "DEC-034"
  - "DEC-049"
  - "WF-ARCH §7"
  - "packages/contracts/schemas/entities/**"
  - "packages/contracts/resources/resources.json"
  - "packages/contracts/identity/*.schema.json"
  - "ownership-matrix.md（Agent-Data）"
  - "REQ-F-017/019/020/021/028/029/032"
  - "REQ-NF-003"
---

# DESIGN-004 数据

## 1. 通则（两侧共同）
| 规则 | 内容 | 依据 |
|---|---|---|
| 引擎 | SQLite ≥ 3.40，WAL，单写者连接 + 多读连接；`PRAGMA foreign_keys=ON; journal_mode=WAL; synchronous=NORMAL; busy_timeout=5000` | ADR-003、迁移头注释 |
| ID | `TEXT`，前缀 + `_` + 26 位 Crockford ULID（`usr_`、`ten_`…）；自增整数只用于纯内部队列表（node 的 `prompt_queue`、`model_usage`、`meeting_events`） | ADR-012、ids.schema.json |
| 时间 | `INTEGER` 毫秒 UTC；API 层转 RFC 3339 | ADR-012 |
| JSON 列 | `TEXT` + `CHECK(json_valid(...))`；结构以契约实体为准，仓储读出后用 ajv 校验 | 迁移头注释 |
| 枚举 | 业务状态用 `CHECK IN`；**渠道 kind、适配器 id、agent kind 不加 CHECK**（新增渠道/智能体不改表） | DEC-008 |
| 软删除 | `deleted_at INTEGER NULL`；唯一索引一律带 `WHERE deleted_at IS NULL` | 迁移头注释 |
| 乐观锁 | 可编辑配置表带 `version`；`UPDATE … SET version=version+1 WHERE id=? AND version=?`，影响 0 行 → `CONFLICT` | error-codes.json |
| append-only | `messages`（触发器禁止改 body/plain_text/direction）、`audit_log`（禁止 UPDATE/DELETE） | DEC-004、REQ-F-028 |
| 加密列 | `*_enc BLOB`：AES-256-GCM（12 字节随机 nonce ‖ 密文 ‖ 16 字节 tag），主密钥：中转 = `WF_MASTER_KEY_FILE`；节点 = 钥匙串 | DEC-004、DEC-020 |
| 列名 | snake_case；与契约 camelCase 字段一一映射（mapper 在 infrastructure） | ADR-012 |

## 2. relay.db（中转）逐表

### 2.1 账号与组织
| 表 | 用途 | 关键字段 | 索引 → 查询路径 | 删除/保留 |
|---|---|---|---|---|
| `schema_migrations` | 已应用迁移版本 | `version` PK | 启动时 `SELECT max(version)` | 永久 |
| `tenants` | 组织（personal/company） | `kind`、`emergency_stopped_at`（急停标志，NULL=未急停） | PK；急停检查按 id 点查 | 软删除；v1 不提供删除端点 |
| `users` | 用户；`password_hash`（argon2id）与 `totp_secret_enc` 绝不出现在契约 | `email COLLATE NOCASE`、`locale` | `ux_users_email`（未删除唯一）→ 登录按邮箱查 | 软删除 |
| `memberships` | 用户 × 组织 × 角色 × 项目范围 | `role`、`project_scope`（JSON 数组，空=全组织）、`version` | `ux_memberships(tenant_id,user_id)` → 鉴权取 principal；成员列表按 tenant | 软删除（移除成员） |
| `web_sessions` | Web 会话（服务端存储） | `id_hash`（Cookie 值 sha256）、`csrf`、`expires_at`、`revoked_at` | PK → 每请求点查；`ix_web_sessions_user` → 登出全部/改密吊销 | 过期 7 天后物理删除（§4） |
| `invitations` | 邀请链接 | `token_hash` PK、`role`、`project_scope`、`expires_at`、`accepted_at` | PK → 接受邀请点查 | 过期 30 天后物理删除 |

### 2.2 设备与节点通道
| 表 | 用途 | 关键字段 | 索引 → 查询路径 | 删除/保留 |
|---|---|---|---|---|
| `devices` | 已配对节点 | `token_hash`、`prev_token_hash`（轮换过渡）、`is_primary`、`last_seen_at`、`last_acked_node_seq`（中转已处理的节点帧序号）、`relay_seq`（中转→该设备的最大已分配 seq）、`revoked_at` | `ux_devices_token` → 握手按令牌哈希查；`ux_devices_primary(tenant_id,owner_user_id) WHERE is_primary=1 AND revoked_at IS NULL` → 每人至多一个主设备、总控定位 | 吊销保留（审计需要），不物理删除 |
| `pairing_codes` | 8 位一次性配对码 | `code` PK、`expires_at`（10 分钟）、`used_at` | PK → claim 点查 | 使用或过期 1 天后删除 |
| `node_outbox` | 中转→节点待确认帧 | `(device_id, seq)` PK、`frame` JSON、`acked_at` | PK 范围扫描 → 重连续传 `seq > lastAckedRelaySeq AND acked_at IS NULL` | ack 后 7 天删除 |
| `node_inbox_dedupe` | 节点→中转帧去重 | `(device_id, idempotency_key)` PK | `INSERT OR IGNORE` 命中即重复 | 7 天后删除（远大于 10 分钟恢复窗口，REQ-NF-003） |

### 2.3 项目与智能体
| 表 | 用途 | 关键字段 | 索引 → 查询路径 | 删除/保留 |
|---|---|---|---|---|
| `projects` | 主/子项目（深度 ≤3，CHECK） | `parent_id`、`depth`、`slug`、`archived` | `ux_projects_slug(tenant_id,slug)`；`ix_projects_parent` → 子树；树页一次取 tenant 全部 | 软删除；归档优先 |
| `agents` | 智能体元数据（运行在节点，由 hello/agents.sync 同步运行态） | `device_id`、`project_id`、`alias`、`adapter_id`（无 CHECK）、`kind`、`workdir`、`write_mode`、`status`、`config` JSON | `ux_agents_alias(tenant_id,alias)` → `@别名`/`/use` 解析；`ix_agents_device` → 设备上线同步、离线排队提示；`ix_agents_project` → 项目视图 | 软删除（别名释放） |

### 2.4 渠道与接收人
| 表 | 用途 | 关键字段 | 索引 → 查询路径 | 删除/保留 |
|---|---|---|---|---|
| `channels` | 渠道实例（含内置 `web`） | `kind`（无 CHECK）、`config` JSON、`credential_enc`、`bot_identity_hash`、`capabilities` JSON、`health`、`cursor`（长轮询游标，如微信 get_updates_buf） | `ux_channels_bot_identity` **跨 tenant 全局唯一** → 一个 Bot 身份一个消费者（DEC-034） | 软删除；删除时清空 credential_enc |
| `channel_tokens` | 每 (渠道, 接收人) 的会话令牌（如微信 context_token）与额度计数 | `token_enc`、`refreshed_at`、`sent_since_refresh` | PK → 发送前点查、入站时 upsert | 渠道删除时级联由应用删除 |
| `recipients` | 渠道上的身份（direct/group/channel） | `platform_id`、`scope`、`linked_user_id`、`authorized`（默认 0）、`quiet_hours` JSON、`bind_code`、`bind_code_expires_at` | `ux_recipients_platform(channel_id,platform_id,scope)` → 入站解析 | 不删除（审计引用）；可取消授权 |
| `recipient_focus` | `/use` 焦点：接收人当前默认智能体 | `recipient_id` PK、`agent_id` | PK 点查（路由第 6 步） | 智能体删除时应用层删除 |

### 2.5 绑定与过滤
| 表 | 用途 | 关键字段 | 索引 → 查询路径 | 删除/保留 |
|---|---|---|---|---|
| `routes` | 绑定（模式 + 默认来源 + 优先级下限） | `mode` CHECK、`default_source_id`、`priority_floor`、`enabled`、`version` | PK | 软删除 |
| `route_sources` | 绑定 × 来源智能体 | `(route_id, agent_id)` PK | PK 前缀 → 出站时“该智能体属于哪些绑定”需反查：**无 agent_id 索引**（§8 D-3） | 随绑定 |
| `route_targets` | 绑定 × 目标接收人 | `(route_id, recipient_id)` PK | `ix_route_targets_recipient` → 入站“该接收人在哪些绑定中” | 随绑定 |
| `route_filters` | 绑定 × 过滤规则（有序） | `ord` | PK；读取后按 ord 排序 | 随绑定 |
| `filter_rules` | 接收人 × 业务线 × 字段规则 | `match` JSON（recipientIds、businessLines）、`action`、`fields` JSON、`mask_style` | PK | 软删除 |

### 2.6 会话与消息
| 表 | 用途 | 关键字段 | 索引 → 查询路径 | 删除/保留 |
|---|---|---|---|---|
| `conversations` | 会话：稳定 id + generation + display_id + native_session_id | `agent_id`、`route_id`、`recipient_id`、`generation`、`display_id`、`state` | `ux_conversations_display(tenant_id,display_id)` → `/history WF-12`；**`ux_conversations_active(agent_id, IFNULL(route_id,''), IFNULL(recipient_id,'')) WHERE state='active'`** → 按发送人分会话（G25）与 get-or-create 的并发安全；`ix_conversations_native` → 按原生 resume id 查 | 软删除（级联附件软删除） |
| `display_id_counters` | displayId 序号分配 | `(tenant_id,prefix)` PK、`next` | 在创建会话的同一事务内 `UPDATE … SET next=next+1 RETURNING` | 永久 |
| `messages` | 消息账本（append-only） | `generation`、`direction`、`author_kind/ref`、`priority`、`body` JSON（IR）、`plain_text`（FTS 用）、`reply_to_id`、`channel_id`、`platform_message_id`、`idempotency_key`、`supervisor_verdict` | `ux_messages_idem` → 入站/节点帧去重；`ix_messages_conv(conversation_id, created_at)` → 消息分页；`ux_messages_platform(channel_id, platform_message_id)` → 入站重复检测与“引用了一条入站消息”的溯源 | 不删除（会话软删后不可见）；保留期见 §4 |
| `messages_fts` | FTS5 trigram（中文子串检索） | `plain_text` | `messages_ai` 触发器同步插入 → `/history/search?q=` | 随 messages |

### 2.7 投递、审批、屏障
| 表 | 用途 | 关键字段 | 索引 → 查询路径 | 删除/保留 |
|---|---|---|---|---|
| `deliveries` | outbox：一条消息 × 一个接收人 | `status`、`attempts`、`next_attempt_at`、`rendered_as`、`rendered_payload`、`filters_applied` JSON、`last_error`、`platform_message_id` | `ux_deliveries(message_id,recipient_id)` → fanout 幂等；`ix_deliveries_due(status,next_attempt_at) WHERE status IN ('queued','failed')` → 工作者取件 | sent 90 天后可清 `rendered_payload`（保留行供审计，设计值） |
| `approvals` | 审批 | `short_code`、`kind`、`risk`、`options` JSON、`status`、`decided_by`、`decided_option`、`expires_at` | `ux_approvals_code(tenant_id,short_code) WHERE status='pending'` → `Y3/N3` 解析与 shortCode 复用；`ix_approvals_pending(status,expires_at)` → 超时工作者、收件箱 | 永久（审计） |
| `held_messages` | 暂存：目标有待审批时的入站 | `agent_id`、`approval_id`、`held_at`、`released_at` | PK；释放时按 `agent_id` + `released_at IS NULL ORDER BY held_at`（**无索引**，§8 D-4） | 释放后保留 |
| `barriers` | 汇总屏障 | `route_id`、`expected_sources` JSON、`timeout_sec`、`status`、`summary_message_id` | PK；超时扫描全表 open 行（数量小） | 永久 |
| `barrier_submissions` | 屏障提交 | `(barrier_id, agent_id)` PK、`message_id` | PK → 重复提交幂等；收齐判断 `count(*)` | 随屏障 |

### 2.8 其他
| 表 | 用途 | 关键字段 | 索引 → 查询路径 | 删除/保留 |
|---|---|---|---|---|
| `attachments` | 附件元数据（文件在 `attachments/{tenantId}/{yyyy}/{mm}/{id}`） | `conversation_id`、`mime`、`size_bytes`、`storage_path`、`sha256` | PK | 默认 90 天（resources.json，组织可配 7–365）；软删 7 天后物理删 |
| `push_subscriptions` | Web Push 订阅 | `endpoint`（唯一）、`p256dh`、`auth`、`min_priority`、`failed_count` | `ux_push_endpoint` → 重复订阅 upsert | 404/410 或失败 ≥5 次删除 |
| `audit_log` | 审计（append-only） | `actor_kind/ref`、`action`、`resource_type/id`、`detail` JSON、`trace_id` | `ix_audit_tenant_time` → 审计页时间范围；`ix_audit_resource` → “这条出站经过哪些过滤”（resource_type='delivery'） | 触发器禁止删除 → **v1 永久保留**（§8 D-6） |
| `idempotency_keys` | HTTP 幂等 | `(principal, key)` PK、`response`、`status` | PK 点查 | 24 h 后删除 |

## 3. node.db（本机节点）逐表
### 3.1 连接与智能体
| 表 | 用途 | 关键字段 | 索引 → 查询路径 | 删除/保留 |
|---|---|---|---|---|
| `relay_links` | 中转连接（多中转） | `url`、`tenant_id`、`device_id`、`token_ref`（钥匙串条目名，令牌不入库）、`last_acked_relay_seq`、`node_seq`、`status`、`revoked_at` | `ux_relay_links_url_tenant` → 同一中转同一组织只连一次 | 删除链接 = 置 revoked_at + 删钥匙串条目 |
| `agents` | 本机智能体；`relay_link_id` 即命名空间 | `adapter_id`、`alias`、`project_id`、`workdir`、`write_mode`、`config` JSON、`status` | `ix_node_agents_link` → 按链接列出/隔离校验 | 软删除 |
| `relay_outbox` | 节点→中转待确认帧 | `(relay_link_id, seq)` PK | 重连续传 | ack 后 7 天删除 |
| `relay_inbox_dedupe` | 中转→节点帧去重 | `(relay_link_id, idempotency_key)` PK | `INSERT OR IGNORE` | 7 天后删除 |

### 3.2 会话、转录、队列
| 表 | 用途 | 关键字段 | 索引 → 查询路径 | 删除/保留 |
|---|---|---|---|---|
| `sessions` | 智能体侧会话（与 relay.conversations 按 `(conversation_id, generation)` 一一对应） | `native_session_id`、`transcript_path`、`state`、`last_active_at` | PK；`ix_sessions_native` → 按原生 id 查 | 永久（用户可删转录） |
| `transcript_index` | 转录行索引（正文在 JSONL 文件） | `(conversation_id, generation, line_no)` PK、`role`、`plain_text` | PK → `history.query` 分页取最近 n 条 | 随会话 |
| `transcript_fts` | FTS5 trigram，`content='transcript_index'` | `plain_text` | **无同步触发器**：由 `transcript-writer` 在同一事务内 `INSERT INTO transcript_fts(rowid, plain_text)`（rowid 取 transcript_index 隐式 rowid） | 随会话 |
| `prompt_queue` | 每会话串行队列 | `message_id` UNIQUE、`state`（queued/running/done/failed/cancelled，设计值）、`payload` | `ix_prompt_queue_conv(conversation_id,state,id)` → 取某会话下一条 queued | done/failed 7 天后删除 |
| `pending_permissions` | ACP 权限请求 ↔ approvalId | `acp_request_id`、`options`、`resolved_at` | PK → approval.decision 点查 | resolved 30 天后删除 |
| `write_leases` | 同目录写租约 | `workdir_canonical`、`mode`（exclusive/worktree）、`worktree_path`、`heartbeat_at`、`released_at` | `ux_write_leases_active(workdir_canonical) WHERE released_at IS NULL AND mode='exclusive'` → 冲突检测原子化 | released 30 天后删除 |

### 3.3 模型、总控、会议、分身、设置
| 表 | 用途 | 关键字段 | 索引 → 查询路径 | 删除/保留 |
|---|---|---|---|---|
| `model_profiles` | 模型配置（Key 只存 `key_ref`） | `provider`、`base_url`、`model`、`params`/`pricing`/`limits` JSON、`system_prompt`、`version` | PK | 软删除 + 删钥匙串条目 |
| `model_usage` | 每次调用的 token 与费用 | `purpose`、`input_tokens`、`output_tokens`、`cost_micros`、`currency` | `ix_model_usage_time(model_profile_id, created_at)` → 日/月汇总与预算检查 | 保留 400 天（覆盖月度对账，设计值） |
| `supervisor_settings` | 总控设置（单行 id=1） | `model_profile_id`、`rules` JSON、`degraded_since` | — | 永久 |
| `supervisor_verdicts` | 每条输出的分级与理由（REQ-F-022） | `verdict` CHECK、`reason`、`by_rules` | PK(message_id) | 永久 |
| `supervisor_tasks` | 分派任务（会议/导入/对话） | `source`、`assigned_agent_id`、`state`、`depends_on` JSON | PK | 永久 |
| `meetings` / `meeting_events` | 会议与结构化事件（可回放） | `kind` CHECK（round_opened/speech/minutes/decision/round_closed） | `ix_meeting_events(meeting_id, round, id)` → 回放 | 永久 |
| `twin_events` | 分身数据（只在节点） | `kind`、`text`、`refs` JSON、`edited_at`、`deleted_at` | `ix_twin_time` → 分页与导出 | 用户软删；导出不含已删 |
| `kv_settings` | 杂项设置（急停标志、本机令牌指纹等） | `key` PK | 点查 | 永久 |

## 4. 软删除与保留期（RetentionSweeper，中转 DESIGN-002 §7.7 / 节点同构）
| 对象 | 规则 | 依据 |
|---|---|---|
| 配置类（tenants、users、memberships、projects、agents、channels、filter_rules、routes、model_profiles） | 软删除；唯一索引排除已删；不物理删除 | 迁移规则 |
| 会话 | 软删除；其附件同时软删除，7 天后物理删文件 | resources.json lifecycle |
| 消息、审批、审计 | v1 不删除（审计与回复溯源依赖） | DEC-004、REQ-F-028 |
| 附件 | 默认 90 天（可配 7–365，见 §8 D-5） | resources.json |
| 协议去重/outbox | ack 后 7 天 | REQ-NF-003（恢复窗口 10 分钟） |
| 会话 Cookie、配对码、幂等键 | 过期后 7 天 / 1 天 / 24 h | session-claims、device-token-claims、openapi 描述 |
| 分身 | 用户自主删除；导出 JSONL | DEC-049 |

## 5. 迁移编排规则
1. **仅追加**：已合并的迁移文件禁止修改（迁移头注释）；每次变更 = 新文件 `NNNN_<snake_desc>.sql`，两侧编号独立（`database/migrations/relay/`、`database/migrations/node/`）。
2. **版本号由 Agent-Data 串行分配**：任何任务需要表结构变更，提交需求给 Agent-Data（ownership-matrix：`database/migrations/**` 仅 Agent-Data 新增），由其按序取下一个号，避免并行分支撞号。
3. **v1 冻结**：0001 为 v1 基线；v1 期间新增迁移只允许**加表、加列（可空或有默认值）、加索引、加触发器**，禁止删列/改列类型/改语义（改语义需 ADR）。
4. 迁移运行器（TASK-003，`core/db/migrate.ts`，relay/node 共用）：启动时读取 `schema_migrations`，按版本升序在**单个事务**内逐个执行未应用文件，文件末尾自行 `INSERT INTO schema_migrations`（与 0001 一致）；任一失败回滚并退出码 70。执行前对数据库做在线备份（`VACUUM INTO '<dataDir>/backup/pre-<version>.db'`，设计值）。
5. 降级：不提供 down 迁移；回滚 = 用升级前备份恢复（PROJECT-STRUCTURE-SPEC §14 精神：用版本化产物而非手改）。
6. Kysely 类型 `core/db/kysely-types.ts` 由迁移后的库自动生成，CI 检查无漂移（同 ADR-002 思路）。
7. 契约优先：新列若会出现在 API，必须先有契约变更（Agent-Contract + ADR），再由 Agent-Data 出迁移。

## 6. ER 关系（文字图）
```text
relay.db
tenants 1─* memberships *─1 users 1─* web_sessions
tenants 1─* invitations
tenants 1─* devices *─1 users(owner)        devices 1─* node_outbox / node_inbox_dedupe
tenants 1─* projects (self: parent_id，depth≤3)
devices 1─* agents *─1 projects
tenants 1─* channels 1─* recipients *─0..1 users(linked)
channels 1─* channel_tokens *─1 recipients(逻辑，无 FK)
recipients 1─0..1 recipient_focus *─1 agents
projects 1─* routes ; routes *─* agents (route_sources) ; routes *─* recipients (route_targets) ; routes *─* filter_rules (route_filters, ord)
agents 1─* conversations *─0..1 routes ; conversations *─0..1 recipients ; conversations *─1 projects
conversations 1─* messages (generation) ; messages 0..1─* messages(reply_to_id) ; messages *─0..1 channels
messages 1─* deliveries *─1 recipients ; deliveries *─1 channels
conversations 1─* approvals *─1 agents ; approvals 1─* held_messages 1─1 messages
routes 1─* barriers 1─* barrier_submissions *─1 messages ; barriers 0..1─1 messages(summary)
conversations 1─* attachments ; users 1─* push_subscriptions ; tenants 1─* audit_log(逻辑)

node.db
relay_links 1─* agents 1─* sessions(conversation_id, generation) 1─* transcript_index ─ transcript_fts
relay_links 1─* relay_outbox / relay_inbox_dedupe
agents 1─* write_leases ; sessions 1─* prompt_queue(逻辑) ; sessions 1─* pending_permissions(逻辑)
model_profiles 1─* model_usage ; model_profiles 0..1─1 supervisor_settings
agents 0..1─* supervisor_tasks ; meetings 1─* meeting_events
twin_events（独立） ; kv_settings（独立）

跨库对应（无外键，按 ID 关联）：relay.conversations.id = node.sessions.conversation_id；relay.agents.id = node.agents.id；relay.approvals.id = node.pending_permissions.approval_id
```

## 7. 关键查询路径 ↔ 索引
| 查询 | SQL 形态 | 索引 |
|---|---|---|
| 入站去重 | `INSERT INTO messages … idempotency_key=?`（冲突即重复） | ux_messages_idem |
| 入站解析接收人 | `WHERE channel_id=? AND platform_id=? AND scope=?` | ux_recipients_platform |
| 该接收人的绑定 | `route_targets WHERE recipient_id=?` → routes enabled | ix_route_targets_recipient |
| 引用回复溯源（引用的是入站） | `messages WHERE channel_id=? AND platform_message_id=?` | ux_messages_platform |
| 引用回复溯源（引用的是我方出站） | `deliveries WHERE channel_id=? AND platform_message_id=?` | **缺**（§8 D-2） |
| 别名解析 | `agents WHERE tenant_id=? AND alias=? AND deleted_at IS NULL` | ux_agents_alias |
| 活跃会话 get-or-create | `conversations WHERE agent_id=? AND route_id IS ? AND recipient_id IS ? AND state='active'` | ux_conversations_active |
| 投递取件 | `deliveries WHERE status IN(...) AND next_attempt_at<=?` | ix_deliveries_due |
| Y/N 审批 | `approvals WHERE tenant_id=? AND short_code=? AND status='pending'` | ux_approvals_code |
| 是否有待审批（held 判定） | `approvals WHERE agent_id=? AND status='pending'` | **无 agent_id 索引**（§8 D-4） |
| 历史检索 | `messages_fts MATCH ?` → join messages → conversations（tenant 过滤） | FTS5 trigram |
| 审计时间范围 | `audit_log WHERE tenant_id=? AND created_at BETWEEN` | ix_audit_tenant_time |

## 8. 与契约的差异 / 待办（需 Agent-Data 新增迁移或契约补充）
| # | 发现 | 建议 |
|---|---|---|
| D-1 | `messages`、`deliveries`、`barriers`、`held_messages` 无 `tenant_id` | 仓储经父表校验；数据量大时追加冗余列 |
| D-2 | 出站溯源需 `deliveries(channel_id, platform_message_id)` 索引 | 0002 加 `ix_deliveries_platform`（同 DESIGN-002 W-10） |
| D-3 | `route_sources` 无 `agent_id` 索引；出站 fanout 每条都要查“该智能体在哪些绑定中” | 0002 加 `ix_route_sources_agent(agent_id)` |
| D-4 | `approvals` 无 `(agent_id, status)` 索引；`held_messages` 无 `(agent_id, released_at)` 索引 | 0002 加 `ix_approvals_agent_pending(agent_id) WHERE status='pending'`、`ix_held_agent(agent_id, held_at) WHERE released_at IS NULL` |
| D-5 | resources.json 允许组织配置附件保留期 7–365 天，但 `tenants` 无设置列 | 0002 加 `tenants.settings TEXT NOT NULL DEFAULT '{}' CHECK(json_valid)`；同时需契约 tenant 实体/端点补字段 |
| D-6 | `audit_log` 触发器禁止 DELETE，保留期无法实施 | v1 永久保留；若需保留期，需 ADR 改为“归档后删除” |
| D-7 | `recipients.bind_code` 无索引且未声明唯一范围 | 0002 加 `ix_recipients_bind_code(bind_code) WHERE bind_code IS NOT NULL`；应用层保证 tenant 内未过期码唯一 |
| D-8 | node `transcript_fts` 无同步触发器 | 应用层同事务维护（DESIGN-003 N-6）；或 0002 加 AFTER INSERT 触发器 |
| D-9 | `conversation.state='cleared'` 语义未定义；`/clear` 只增 generation | v1 不使用 `cleared`（保持 active），避免触碰 ux_conversations_active；建议契约说明 |
| D-10 | node 无 hooks 表、无绑定缓存表（WF-ARCH §7 写有“缓存只读副本”） | v1 不缓存；hook 存 `agents.config`（DESIGN-003 N-5/N-7） |
| D-11 | `prompt_queue.state` 无 CHECK 与枚举定义 | 本文定为 queued/running/done/failed/cancelled；建议 0002 加 CHECK |
