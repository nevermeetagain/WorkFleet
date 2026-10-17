-- WorkFleet relay schema v1 (SQLite >= 3.40, WAL). 数据模型基线：docs/WorkFleet-V0.0.4/03_solution/design/DESIGN-004-数据.md
-- 规则：ID = 前缀+ULID（TEXT）；时间 = INTEGER 毫秒 UTC；JSON 列存 TEXT 并 CHECK(json_valid)；渠道/适配器类型不做 CHECK 枚举（DEC-008）；
-- 软删除用 deleted_at；乐观锁用 version。迁移只追加新文件，禁止修改已合并文件。
PRAGMA foreign_keys = ON;

CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL);

CREATE TABLE tenants (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL CHECK (kind IN ('personal','company')),
  emergency_stopped_at INTEGER, created_at INTEGER NOT NULL, deleted_at INTEGER
);
CREATE TABLE users (
  id TEXT PRIMARY KEY, email TEXT NOT NULL COLLATE NOCASE, password_hash TEXT NOT NULL, display_name TEXT NOT NULL,
  locale TEXT NOT NULL DEFAULT 'zh-CN', totp_secret_enc BLOB, created_at INTEGER NOT NULL, deleted_at INTEGER
);
CREATE UNIQUE INDEX ux_users_email ON users(email) WHERE deleted_at IS NULL;
CREATE TABLE memberships (
  id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(id), user_id TEXT NOT NULL REFERENCES users(id),
  role TEXT NOT NULL CHECK (role IN ('admin','operator','viewer')), project_scope TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(project_scope)),
  version INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL, deleted_at INTEGER
);
CREATE UNIQUE INDEX ux_memberships ON memberships(tenant_id, user_id) WHERE deleted_at IS NULL;
CREATE TABLE web_sessions (
  id_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), tenant_id TEXT NOT NULL REFERENCES tenants(id),
  csrf TEXT NOT NULL, issued_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, revoked_at INTEGER
);
CREATE INDEX ix_web_sessions_user ON web_sessions(user_id);
CREATE TABLE invitations (
  token_hash TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(id), email TEXT NOT NULL, role TEXT NOT NULL,
  project_scope TEXT NOT NULL DEFAULT '[]', expires_at INTEGER NOT NULL, accepted_at INTEGER, created_by TEXT NOT NULL REFERENCES users(id)
);

CREATE TABLE devices (
  id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(id), owner_user_id TEXT NOT NULL REFERENCES users(id),
  name TEXT NOT NULL, os TEXT NOT NULL CHECK (os IN ('windows','macos','linux')), node_version TEXT NOT NULL,
  is_primary INTEGER NOT NULL DEFAULT 0, token_hash TEXT NOT NULL, prev_token_hash TEXT,
  last_seen_at INTEGER, last_acked_node_seq INTEGER NOT NULL DEFAULT 0, relay_seq INTEGER NOT NULL DEFAULT 0,
  revoked_at INTEGER, created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX ux_devices_token ON devices(token_hash);
CREATE UNIQUE INDEX ux_devices_primary ON devices(tenant_id, owner_user_id) WHERE is_primary = 1 AND revoked_at IS NULL;
CREATE TABLE pairing_codes (
  code TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(id), user_id TEXT NOT NULL REFERENCES users(id),
  expires_at INTEGER NOT NULL, used_at INTEGER
);

CREATE TABLE projects (
  id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(id), parent_id TEXT REFERENCES projects(id),
  name TEXT NOT NULL, slug TEXT NOT NULL, depth INTEGER NOT NULL CHECK (depth BETWEEN 1 AND 3), archived INTEGER NOT NULL DEFAULT 0,
  version INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL, deleted_at INTEGER
);
CREATE UNIQUE INDEX ux_projects_slug ON projects(tenant_id, slug) WHERE deleted_at IS NULL;
CREATE INDEX ix_projects_parent ON projects(parent_id);

CREATE TABLE agents (
  id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(id), device_id TEXT NOT NULL REFERENCES devices(id),
  project_id TEXT NOT NULL REFERENCES projects(id), alias TEXT NOT NULL, adapter_id TEXT NOT NULL, kind TEXT NOT NULL,
  workdir TEXT NOT NULL, write_mode TEXT NOT NULL CHECK (write_mode IN ('read_only','write')), status TEXT NOT NULL DEFAULT 'idle',
  experimental INTEGER NOT NULL DEFAULT 0, config TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(config)),
  version INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL, deleted_at INTEGER
);
CREATE UNIQUE INDEX ux_agents_alias ON agents(tenant_id, alias) WHERE deleted_at IS NULL;
CREATE INDEX ix_agents_device ON agents(device_id);
CREATE INDEX ix_agents_project ON agents(project_id);

CREATE TABLE channels (
  id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(id), kind TEXT NOT NULL, name TEXT NOT NULL,
  config TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(config)), credential_enc BLOB, bot_identity_hash TEXT,
  capabilities TEXT NOT NULL CHECK (json_valid(capabilities)), health TEXT NOT NULL DEFAULT 'disabled',
  cursor TEXT, version INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL, deleted_at INTEGER
);
-- 一个 Bot 身份一个消费者（DEC-034）：跨 tenant 全局唯一
CREATE UNIQUE INDEX ux_channels_bot_identity ON channels(bot_identity_hash) WHERE bot_identity_hash IS NOT NULL AND deleted_at IS NULL;
CREATE TABLE channel_tokens (  -- 如微信 context_token：按 (channel, recipient) 持久化并加密
  channel_id TEXT NOT NULL REFERENCES channels(id), recipient_id TEXT NOT NULL, token_enc BLOB NOT NULL,
  refreshed_at INTEGER NOT NULL, sent_since_refresh INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (channel_id, recipient_id)
);

CREATE TABLE recipients (
  id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(id), channel_id TEXT NOT NULL REFERENCES channels(id),
  platform_id TEXT NOT NULL, scope TEXT NOT NULL CHECK (scope IN ('direct','group','channel')), display_name TEXT NOT NULL,
  linked_user_id TEXT REFERENCES users(id), authorized INTEGER NOT NULL DEFAULT 0, quiet_hours TEXT CHECK (quiet_hours IS NULL OR json_valid(quiet_hours)),
  bind_code TEXT, bind_code_expires_at INTEGER, version INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX ux_recipients_platform ON recipients(channel_id, platform_id, scope);

CREATE TABLE filter_rules (
  id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(id), name TEXT NOT NULL,
  match TEXT NOT NULL CHECK (json_valid(match)), action TEXT NOT NULL CHECK (action IN ('allow_fields','mask_fields','drop_message')),
  fields TEXT NOT NULL CHECK (json_valid(fields)), mask_style TEXT NOT NULL DEFAULT 'partial',
  version INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL, deleted_at INTEGER
);

CREATE TABLE routes (
  id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(id), project_id TEXT NOT NULL REFERENCES projects(id),
  name TEXT NOT NULL, mode TEXT NOT NULL CHECK (mode IN ('management','notification','team','supervisor')),
  default_source_id TEXT REFERENCES agents(id), priority_floor TEXT NOT NULL DEFAULT 'p3', enabled INTEGER NOT NULL DEFAULT 1,
  version INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL, deleted_at INTEGER
);
CREATE TABLE route_sources (route_id TEXT NOT NULL REFERENCES routes(id), agent_id TEXT NOT NULL REFERENCES agents(id), PRIMARY KEY (route_id, agent_id));
CREATE TABLE route_targets (route_id TEXT NOT NULL REFERENCES routes(id), recipient_id TEXT NOT NULL REFERENCES recipients(id), PRIMARY KEY (route_id, recipient_id));
CREATE INDEX ix_route_targets_recipient ON route_targets(recipient_id);
CREATE TABLE route_filters (route_id TEXT NOT NULL REFERENCES routes(id), filter_rule_id TEXT NOT NULL REFERENCES filter_rules(id), ord INTEGER NOT NULL, PRIMARY KEY (route_id, filter_rule_id));
-- 当前默认目标（/use）：按 (recipient) 保存
CREATE TABLE recipient_focus (recipient_id TEXT PRIMARY KEY REFERENCES recipients(id), agent_id TEXT NOT NULL REFERENCES agents(id), updated_at INTEGER NOT NULL);

CREATE TABLE conversations (
  id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(id), project_id TEXT NOT NULL REFERENCES projects(id),
  agent_id TEXT NOT NULL REFERENCES agents(id), route_id TEXT REFERENCES routes(id), recipient_id TEXT REFERENCES recipients(id),
  generation INTEGER NOT NULL DEFAULT 1, display_id TEXT NOT NULL, native_session_id TEXT, title TEXT NOT NULL DEFAULT '',
  state TEXT NOT NULL DEFAULT 'active' CHECK (state IN ('active','cleared','closed')), created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER
);
CREATE UNIQUE INDEX ux_conversations_display ON conversations(tenant_id, display_id);
-- 按发送人分会话（G25）与默认会话：同一 (agent, route, recipient) 只有一个 active
CREATE UNIQUE INDEX ux_conversations_active ON conversations(agent_id, IFNULL(route_id,''), IFNULL(recipient_id,'')) WHERE state = 'active' AND deleted_at IS NULL;
CREATE INDEX ix_conversations_native ON conversations(native_session_id) WHERE native_session_id IS NOT NULL;
CREATE TABLE display_id_counters (tenant_id TEXT NOT NULL, prefix TEXT NOT NULL, next INTEGER NOT NULL, PRIMARY KEY (tenant_id, prefix));

CREATE TABLE messages (  -- append-only 账本
  id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL REFERENCES conversations(id), generation INTEGER NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('inbound','outbound','system')), author_kind TEXT NOT NULL, author_ref TEXT NOT NULL,
  priority TEXT NOT NULL DEFAULT 'p2', body TEXT NOT NULL CHECK (json_valid(body)), plain_text TEXT NOT NULL DEFAULT '',
  reply_to_id TEXT REFERENCES messages(id), channel_id TEXT REFERENCES channels(id), platform_message_id TEXT,
  idempotency_key TEXT NOT NULL, supervisor_verdict TEXT, created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX ux_messages_idem ON messages(idempotency_key);
CREATE INDEX ix_messages_conv ON messages(conversation_id, created_at);
-- 回复溯源（G2）：平台消息 id → 我方消息
CREATE UNIQUE INDEX ux_messages_platform ON messages(channel_id, platform_message_id) WHERE platform_message_id IS NOT NULL;
CREATE VIRTUAL TABLE messages_fts USING fts5(plain_text, content='messages', content_rowid='rowid', tokenize='trigram');
CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN INSERT INTO messages_fts(rowid, plain_text) VALUES (new.rowid, new.plain_text); END;
CREATE TRIGGER messages_no_update BEFORE UPDATE OF body, plain_text, direction ON messages BEGIN SELECT RAISE(ABORT, 'messages is append-only'); END;

CREATE TABLE deliveries (  -- outbox；表即队列
  id TEXT PRIMARY KEY, message_id TEXT NOT NULL REFERENCES messages(id), recipient_id TEXT NOT NULL REFERENCES recipients(id),
  channel_id TEXT NOT NULL REFERENCES channels(id), status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','sending','sent','failed','dead','suppressed')),
  attempts INTEGER NOT NULL DEFAULT 0, next_attempt_at INTEGER NOT NULL, rendered_as TEXT NOT NULL DEFAULT 'text',
  filters_applied TEXT NOT NULL DEFAULT '[]', rendered_payload TEXT, last_error TEXT, platform_message_id TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX ux_deliveries ON deliveries(message_id, recipient_id);
CREATE INDEX ix_deliveries_due ON deliveries(status, next_attempt_at) WHERE status IN ('queued','failed');

CREATE TABLE approvals (
  id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(id), conversation_id TEXT NOT NULL REFERENCES conversations(id),
  agent_id TEXT NOT NULL REFERENCES agents(id), short_code INTEGER NOT NULL, kind TEXT NOT NULL, summary TEXT NOT NULL,
  risk TEXT NOT NULL CHECK (risk IN ('low','medium','high')), options TEXT NOT NULL CHECK (json_valid(options)),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','expired','cancelled')),
  decided_by TEXT, decided_option TEXT, expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL, decided_at INTEGER
);
CREATE UNIQUE INDEX ux_approvals_code ON approvals(tenant_id, short_code) WHERE status = 'pending';
CREATE INDEX ix_approvals_pending ON approvals(status, expires_at);
CREATE TABLE held_messages (message_id TEXT PRIMARY KEY REFERENCES messages(id), agent_id TEXT NOT NULL REFERENCES agents(id), approval_id TEXT NOT NULL REFERENCES approvals(id), held_at INTEGER NOT NULL, released_at INTEGER);

CREATE TABLE barriers (
  id TEXT PRIMARY KEY, route_id TEXT NOT NULL REFERENCES routes(id), expected_sources TEXT NOT NULL CHECK (json_valid(expected_sources)),
  timeout_sec INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'open', opened_at INTEGER NOT NULL, closed_at INTEGER, summary_message_id TEXT REFERENCES messages(id)
);
CREATE TABLE barrier_submissions (barrier_id TEXT NOT NULL REFERENCES barriers(id), agent_id TEXT NOT NULL REFERENCES agents(id), message_id TEXT NOT NULL REFERENCES messages(id), submitted_at INTEGER NOT NULL, PRIMARY KEY (barrier_id, agent_id));

CREATE TABLE node_outbox (  -- 中转→节点帧（按设备 seq），ack 前可重放
  device_id TEXT NOT NULL REFERENCES devices(id), seq INTEGER NOT NULL, frame TEXT NOT NULL CHECK (json_valid(frame)),
  created_at INTEGER NOT NULL, acked_at INTEGER, PRIMARY KEY (device_id, seq)
);
CREATE TABLE node_inbox_dedupe (device_id TEXT NOT NULL, idempotency_key TEXT NOT NULL, received_at INTEGER NOT NULL, PRIMARY KEY (device_id, idempotency_key));

CREATE TABLE attachments (
  id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(id), conversation_id TEXT REFERENCES conversations(id),
  name TEXT NOT NULL, mime TEXT NOT NULL, size_bytes INTEGER NOT NULL, storage_path TEXT NOT NULL, sha256 TEXT NOT NULL,
  created_at INTEGER NOT NULL, deleted_at INTEGER
);

CREATE TABLE push_subscriptions (
  id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), endpoint TEXT NOT NULL, p256dh TEXT NOT NULL, auth TEXT NOT NULL,
  min_priority TEXT NOT NULL DEFAULT 'p1', created_at INTEGER NOT NULL, failed_count INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX ux_push_endpoint ON push_subscriptions(endpoint);

CREATE TABLE audit_log (  -- append-only
  id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL, actor_kind TEXT NOT NULL, actor_ref TEXT NOT NULL, action TEXT NOT NULL,
  resource_type TEXT NOT NULL, resource_id TEXT NOT NULL, detail TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(detail)),
  trace_id TEXT NOT NULL, created_at INTEGER NOT NULL
);
CREATE INDEX ix_audit_tenant_time ON audit_log(tenant_id, created_at);
CREATE INDEX ix_audit_resource ON audit_log(resource_type, resource_id);
CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_log BEGIN SELECT RAISE(ABORT, 'audit_log is append-only'); END;
CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_log BEGIN SELECT RAISE(ABORT, 'audit_log is append-only'); END;

CREATE TABLE idempotency_keys (key TEXT NOT NULL, principal TEXT NOT NULL, response TEXT NOT NULL, status INTEGER NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (principal, key));

INSERT INTO schema_migrations(version, applied_at) VALUES (1, CAST(strftime('%s','now') AS INTEGER) * 1000);
