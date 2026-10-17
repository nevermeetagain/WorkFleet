-- CR-001（ADR-015）：规划评审发现的数据缺口。v1 开工前合入；之后 0001/0002 均冻结。
ALTER TABLE tenants ADD COLUMN attachment_retention_days INTEGER NOT NULL DEFAULT 90 CHECK (attachment_retention_days BETWEEN 7 AND 365);
ALTER TABLE tenants ADD COLUMN emergency_reason TEXT;
ALTER TABLE messages ADD COLUMN tenant_id TEXT REFERENCES tenants(id);
ALTER TABLE messages ADD COLUMN untrusted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE messages ADD COLUMN supersedes_message_id TEXT REFERENCES messages(id);
ALTER TABLE deliveries ADD COLUMN tenant_id TEXT REFERENCES tenants(id);
ALTER TABLE barriers ADD COLUMN tenant_id TEXT REFERENCES tenants(id);
ALTER TABLE routes ADD COLUMN created_by TEXT REFERENCES users(id);
ALTER TABLE memberships ADD COLUMN invited_by TEXT REFERENCES users(id);
ALTER TABLE agents ADD COLUMN supervised INTEGER NOT NULL DEFAULT 0;
CREATE INDEX ix_messages_tenant_time ON messages(tenant_id, created_at);
CREATE INDEX ix_deliveries_tenant ON deliveries(tenant_id, created_at);
-- 回复溯源（G2）：用户引用的是“我方发出的那条”，平台 id 记录在 deliveries
CREATE INDEX ix_deliveries_platform ON deliveries(channel_id, platform_message_id) WHERE platform_message_id IS NOT NULL;
CREATE INDEX ix_route_sources_agent ON route_sources(agent_id);
CREATE INDEX ix_approvals_agent_pending ON approvals(agent_id) WHERE status = 'pending';
CREATE INDEX ix_held_agent ON held_messages(agent_id) WHERE released_at IS NULL;
CREATE INDEX ix_recipients_bind_code ON recipients(bind_code) WHERE bind_code IS NOT NULL;
-- 已读状态（跨项目视图未读数）
CREATE TABLE conversation_reads (conversation_id TEXT NOT NULL REFERENCES conversations(id), user_id TEXT NOT NULL REFERENCES users(id), last_read_message_id TEXT REFERENCES messages(id), read_at INTEGER NOT NULL, PRIMARY KEY (conversation_id, user_id));
-- 通知设置与备用渠道（REQ-F-030）
CREATE TABLE notification_settings (user_id TEXT PRIMARY KEY REFERENCES users(id), min_priority_web_push TEXT NOT NULL DEFAULT 'p1', fallback_recipient_ids TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(fallback_recipient_ids)), health_alerts_enabled INTEGER NOT NULL DEFAULT 1, version INTEGER NOT NULL DEFAULT 1, updated_at INTEGER NOT NULL);
CREATE TABLE totp_pending (user_id TEXT PRIMARY KEY REFERENCES users(id), secret_enc BLOB NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE notifications_sent (id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL, user_id TEXT, priority TEXT NOT NULL, kind TEXT NOT NULL, via TEXT NOT NULL, created_at INTEGER NOT NULL);
-- FTS 删除同步（消息只有组织删除时才物理删除）
CREATE TRIGGER messages_ad AFTER DELETE ON messages BEGIN INSERT INTO messages_fts(messages_fts, rowid, plain_text) VALUES ('delete', old.rowid, old.plain_text); END;
-- 审计保留：append-only 触发器改为“仅允许保留期清理”——清理任务先写 kv 标记再删除
DROP TRIGGER audit_no_delete;
CREATE TABLE maintenance_flags (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_log WHEN (SELECT value FROM maintenance_flags WHERE key = 'audit_retention_purge') IS NOT '1' OR old.created_at > (CAST(strftime('%s','now') AS INTEGER) - 400*86400) * 1000 BEGIN SELECT RAISE(ABORT, 'audit_log delete only via retention purge of entries older than 400 days'); END;
-- conversation.state='cleared'：仅在 /clear 后的旧 generation 视图中使用；当前行始终 active，generation 递增（DESIGN-004）
INSERT INTO schema_migrations(version, applied_at) VALUES (2, CAST(strftime('%s','now') AS INTEGER) * 1000);
