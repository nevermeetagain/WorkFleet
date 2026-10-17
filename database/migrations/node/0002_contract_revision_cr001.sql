-- CR-001（ADR-015）
ALTER TABLE twin_events ADD COLUMN relay_link_id TEXT REFERENCES relay_links(id);
ALTER TABLE model_usage ADD COLUMN estimated INTEGER NOT NULL DEFAULT 0;
ALTER TABLE model_usage ADD COLUMN trace_id TEXT;
ALTER TABLE agents ADD COLUMN supervised INTEGER NOT NULL DEFAULT 0;
CREATE TABLE webhook_hooks (id TEXT PRIMARY KEY, agent_id TEXT NOT NULL REFERENCES agents(id), name TEXT NOT NULL, secret_ref TEXT NOT NULL, default_priority TEXT NOT NULL DEFAULT 'p2', created_at INTEGER NOT NULL, deleted_at INTEGER);
CREATE TABLE webhook_dedupe (hook_id TEXT NOT NULL, delivery_id TEXT NOT NULL, received_at INTEGER NOT NULL, PRIMARY KEY (hook_id, delivery_id));
CREATE TABLE pending_conversation_opens (request_id TEXT PRIMARY KEY, relay_link_id TEXT NOT NULL REFERENCES relay_links(id), agent_id TEXT NOT NULL, purpose TEXT NOT NULL, created_at INTEGER NOT NULL, conversation_id TEXT);
CREATE TRIGGER transcript_ai AFTER INSERT ON transcript_index BEGIN INSERT INTO transcript_fts(rowid, plain_text) VALUES (new.rowid, new.plain_text); END;
CREATE TRIGGER transcript_ad AFTER DELETE ON transcript_index BEGIN INSERT INTO transcript_fts(transcript_fts, rowid, plain_text) VALUES ('delete', old.rowid, old.plain_text); END;
INSERT INTO schema_migrations(version, applied_at) VALUES (2, CAST(strftime('%s','now') AS INTEGER) * 1000);
