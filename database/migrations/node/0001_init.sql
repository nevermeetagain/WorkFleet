-- WorkFleet node schema v1 (SQLite WAL)。只存在用户电脑上。见 DESIGN-004。
PRAGMA foreign_keys = ON;
CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL);

CREATE TABLE relay_links (
  id TEXT PRIMARY KEY, label TEXT NOT NULL, url TEXT NOT NULL, tenant_id TEXT NOT NULL, device_id TEXT NOT NULL,
  token_ref TEXT NOT NULL,            -- 钥匙串条目名；令牌不入库
  last_acked_relay_seq INTEGER NOT NULL DEFAULT 0, node_seq INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'disconnected', created_at INTEGER NOT NULL, revoked_at INTEGER
);
CREATE UNIQUE INDEX ux_relay_links_url_tenant ON relay_links(url, tenant_id);

CREATE TABLE agents (  -- 每条中转连接各自的命名空间（DEC-048）
  id TEXT PRIMARY KEY, relay_link_id TEXT NOT NULL REFERENCES relay_links(id), adapter_id TEXT NOT NULL, alias TEXT NOT NULL,
  project_id TEXT NOT NULL, workdir TEXT NOT NULL, write_mode TEXT NOT NULL, config TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(config)),
  status TEXT NOT NULL DEFAULT 'idle', created_at INTEGER NOT NULL, deleted_at INTEGER
);
CREATE INDEX ix_node_agents_link ON agents(relay_link_id);

CREATE TABLE sessions (  -- 智能体侧会话（与 relay.conversations 一一对应）
  conversation_id TEXT NOT NULL, generation INTEGER NOT NULL, agent_id TEXT NOT NULL REFERENCES agents(id),
  native_session_id TEXT, transcript_path TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'active',
  started_at INTEGER NOT NULL, last_active_at INTEGER NOT NULL, PRIMARY KEY (conversation_id, generation)
);
CREATE INDEX ix_sessions_native ON sessions(native_session_id) WHERE native_session_id IS NOT NULL;
CREATE TABLE transcript_index (  -- 转录正文存 JSONL 文件；此表供检索
  conversation_id TEXT NOT NULL, generation INTEGER NOT NULL, line_no INTEGER NOT NULL, role TEXT NOT NULL,
  plain_text TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (conversation_id, generation, line_no)
);
CREATE VIRTUAL TABLE transcript_fts USING fts5(plain_text, content='transcript_index', tokenize='trigram');

CREATE TABLE relay_outbox (relay_link_id TEXT NOT NULL REFERENCES relay_links(id), seq INTEGER NOT NULL, frame TEXT NOT NULL CHECK (json_valid(frame)), created_at INTEGER NOT NULL, acked_at INTEGER, PRIMARY KEY (relay_link_id, seq));
CREATE TABLE relay_inbox_dedupe (relay_link_id TEXT NOT NULL, idempotency_key TEXT NOT NULL, received_at INTEGER NOT NULL, PRIMARY KEY (relay_link_id, idempotency_key));
CREATE TABLE prompt_queue (  -- 每会话串行执行
  id INTEGER PRIMARY KEY AUTOINCREMENT, conversation_id TEXT NOT NULL, generation INTEGER NOT NULL, message_id TEXT NOT NULL UNIQUE,
  payload TEXT NOT NULL CHECK (json_valid(payload)), state TEXT NOT NULL DEFAULT 'queued', enqueued_at INTEGER NOT NULL, started_at INTEGER, finished_at INTEGER
);
CREATE INDEX ix_prompt_queue_conv ON prompt_queue(conversation_id, state, id);

CREATE TABLE write_leases (  -- G10：同一目录一个写入者
  id TEXT PRIMARY KEY, workdir_canonical TEXT NOT NULL, agent_id TEXT NOT NULL REFERENCES agents(id), mode TEXT NOT NULL CHECK (mode IN ('exclusive','worktree')),
  worktree_path TEXT, acquired_at INTEGER NOT NULL, heartbeat_at INTEGER NOT NULL, released_at INTEGER
);
CREATE UNIQUE INDEX ux_write_leases_active ON write_leases(workdir_canonical) WHERE released_at IS NULL AND mode = 'exclusive';

CREATE TABLE pending_permissions (approval_id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, acp_request_id TEXT NOT NULL, options TEXT NOT NULL, created_at INTEGER NOT NULL, resolved_at INTEGER);

CREATE TABLE model_profiles (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, provider TEXT NOT NULL, base_url TEXT NOT NULL, model TEXT NOT NULL, key_ref TEXT NOT NULL,
  params TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(params)), pricing TEXT NOT NULL CHECK (json_valid(pricing)), limits TEXT NOT NULL CHECK (json_valid(limits)),
  system_prompt TEXT NOT NULL DEFAULT '', version INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL, deleted_at INTEGER
);
CREATE TABLE model_usage (
  id INTEGER PRIMARY KEY AUTOINCREMENT, model_profile_id TEXT NOT NULL REFERENCES model_profiles(id), purpose TEXT NOT NULL,
  input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL, cost_micros INTEGER NOT NULL, currency TEXT NOT NULL, created_at INTEGER NOT NULL
);
CREATE INDEX ix_model_usage_time ON model_usage(model_profile_id, created_at);

CREATE TABLE supervisor_settings (id INTEGER PRIMARY KEY CHECK (id = 1), model_profile_id TEXT REFERENCES model_profiles(id), rules TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(rules)), system_prompt TEXT NOT NULL DEFAULT '', degraded_since INTEGER, updated_at INTEGER NOT NULL);
CREATE TABLE supervisor_verdicts (message_id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, verdict TEXT NOT NULL CHECK (verdict IN ('reply','merge','escalate','drop')), reason TEXT NOT NULL, by_rules INTEGER NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE supervisor_tasks (id TEXT PRIMARY KEY, source TEXT NOT NULL CHECK (source IN ('meeting','import','chat')), title TEXT NOT NULL, spec TEXT NOT NULL, assigned_agent_id TEXT REFERENCES agents(id), state TEXT NOT NULL DEFAULT 'pending', depends_on TEXT NOT NULL DEFAULT '[]', created_at INTEGER NOT NULL, finished_at INTEGER);

CREATE TABLE meetings (id TEXT PRIMARY KEY, topic TEXT NOT NULL, participants TEXT NOT NULL CHECK (json_valid(participants)), policy TEXT NOT NULL, round_timeout_sec INTEGER NOT NULL, max_rounds INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'open', created_at INTEGER NOT NULL);
CREATE TABLE meeting_events (id INTEGER PRIMARY KEY AUTOINCREMENT, meeting_id TEXT NOT NULL REFERENCES meetings(id), round INTEGER NOT NULL, kind TEXT NOT NULL CHECK (kind IN ('round_opened','speech','minutes','decision','round_closed')), agent_id TEXT, content TEXT NOT NULL, created_at INTEGER NOT NULL);
CREATE INDEX ix_meeting_events ON meeting_events(meeting_id, round, id);

CREATE TABLE twin_events (
  id TEXT PRIMARY KEY, kind TEXT NOT NULL, text TEXT NOT NULL, refs TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(refs)),
  duration_ms INTEGER, created_at INTEGER NOT NULL, edited_at INTEGER, deleted_at INTEGER
);
CREATE INDEX ix_twin_time ON twin_events(created_at);

CREATE TABLE kv_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL);
INSERT INTO schema_migrations(version, applied_at) VALUES (1, CAST(strftime('%s','now') AS INTEGER) * 1000);
