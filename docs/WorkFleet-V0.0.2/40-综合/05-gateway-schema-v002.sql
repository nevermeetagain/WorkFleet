-- WorkFleet Gateway schema V0.0.2（data/gateway.db）
-- 设计稿：2026-10-17。基线 = _V0.0.1基线/40-综合/04 §6 + 05 §7；本版改动以 [V0.0.2] 标注。
-- 约定：主键 ULID 文本；时间 UTC ISO-8601 文本；JSON 列 TEXT + json_valid CHECK；密钥只存 secret.id 引用。
-- 持久化队列四原则（借 PentAGI RFC flow_concurrency.md，只借设计）：持久化(落表)、可见(status+position)、可管理(cancel/reprioritize)、显式晋升(只有调度器把 queued→running)。
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=5000;

CREATE TABLE schema_version (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL, note TEXT);

-- ===== 设备与密钥 =====
CREATE TABLE device (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, os TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'edge' CHECK (role IN ('edge','hub')),
  last_seen_at TEXT, created_at TEXT NOT NULL
);
CREATE TABLE secret (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('bot_token','app_secret','api_key','oauth','webhook_secret','context_token','other')),
  label TEXT NOT NULL,
  ciphertext BLOB NOT NULL, nonce BLOB NOT NULL, key_version INTEGER NOT NULL,
  created_at TEXT NOT NULL, rotated_at TEXT
);

-- ===== 配置版本化 [V0.0.2] (R-111/R-112/R-921, G39) =====
CREATE TABLE config_revision (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  scope TEXT NOT NULL CHECK (scope IN ('binding','agent_profile','channel_account','schedule','sv_config','subscription_group','content_source','all')),
  snapshot_json TEXT NOT NULL CHECK (json_valid(snapshot_json)),
  diff_json TEXT CHECK (diff_json IS NULL OR json_valid(diff_json)),
  dry_run_json TEXT CHECK (dry_run_json IS NULL OR json_valid(dry_run_json)),   -- 路由预演结果
  status TEXT NOT NULL DEFAULT 'applied' CHECK (status IN ('draft','applied','rolled_back')),
  actor TEXT NOT NULL, created_at TEXT NOT NULL
);

-- ===== 输入端（Agent）：ACP 为长期契约 [V0.0.2] =====
CREATE TABLE agent_profile (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,                         -- 别名，如 claude-a
  family TEXT NOT NULL CHECK (family IN ('acp','stdio-custom','http-cloud','http-inbound','cli-oneshot','supervisor')),  -- [V0.0.2] +http-inbound (G30)
  protocol TEXT NOT NULL DEFAULT 'acp-v1' CHECK (protocol IN ('acp-v1','acp-v2','zcode-appserver','coze-v3','webhook','cli')),  -- [V0.0.2] 编解码器选择
  kind TEXT NOT NULL,                         -- claude/codex/cursor/openclaw/zcode/coze/...
  device_id TEXT REFERENCES device(id),
  launch_json TEXT CHECK (launch_json IS NULL OR json_valid(launch_json)),   -- {cmd,args,env,cwd,pin_version,install_policy} [V0.0.2] pin_version/install_policy (G34)
  http_json TEXT CHECK (http_json IS NULL OR json_valid(http_json)),
  permission_policy TEXT NOT NULL DEFAULT 'ask' CHECK (permission_policy IN ('ask','auto-low-risk','deny-unattended')),
  caps_json TEXT CHECK (caps_json IS NULL OR json_valid(caps_json)),         -- 最近一次 initialize 协商结果（loadSession/sessionCapabilities…）
  caps_negotiated_at TEXT,
  max_parallel_sessions INTEGER NOT NULL DEFAULT 4 CHECK (max_parallel_sessions BETWEEN 1 AND 64),   -- R-208
  tags_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(tags_json)),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX ux_agent_profile_name ON agent_profile(name);
CREATE TABLE agent_version_check (                -- [V0.0.2] 升级前冒烟 (G34, K-05)
  id TEXT PRIMARY KEY, profile_id TEXT NOT NULL REFERENCES agent_profile(id),
  version TEXT NOT NULL, result TEXT NOT NULL CHECK (result IN ('pass','fail')),
  steps_json TEXT NOT NULL CHECK (json_valid(steps_json)), checked_at TEXT NOT NULL
);

-- ===== 输出端 =====
CREATE TABLE channel_account (
  id TEXT PRIMARY KEY,
  adapter TEXT NOT NULL CHECK (adapter IN ('wechat-ilink','feishu','qq','dingtalk','discord','telegram','plugin')),
  credential_secret_id TEXT REFERENCES secret(id),
  credential_fingerprint TEXT NOT NULL,        -- 连接单例池键 (G01, R-309)
  owner_peer_id TEXT,
  timezone TEXT NOT NULL DEFAULT 'Asia/Shanghai',
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('pending_bind','active','expired','paused','disabled')),
  caps_json TEXT CHECK (caps_json IS NULL OR json_valid(caps_json)),
  cursor_json TEXT,                            -- iLink get_updates_buf 等
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX ux_channel_cred ON channel_account(adapter, credential_fingerprint);

CREATE TABLE im_principal (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES channel_account(id),
  peer_id TEXT NOT NULL, peer_type TEXT NOT NULL CHECK (peer_type IN ('user','group','channel')),
  display_name TEXT,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner','admin','member','subscriber','blocked')),
  ctx_secret_id TEXT REFERENCES secret(id),    -- [V0.0.2] context_token 等平台上下文加密存储（修复 WCB 内存 LRU）
  ctx_expires_at TEXT,
  last_inbound_at TEXT,
  UNIQUE(account_id, peer_id)
);

-- ===== 路由：绑定表（四模式）=====
CREATE TABLE binding (
  id TEXT PRIMARY KEY, name TEXT NOT NULL,
  mode TEXT NOT NULL CHECK (mode IN ('management','notification','team','supervisor')),
  direction TEXT NOT NULL DEFAULT 'both' CHECK (direction IN ('both','in-only','out-only')),
  reply_target TEXT NOT NULL DEFAULT 'last-active' CHECK (reply_target IN ('last-active','pinned','ask','supervisor')),
  pinned_profile_id TEXT REFERENCES agent_profile(id),
  filter_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(filter_json)),   -- {kinds:[],minPrio,categories:[],tags:[]}  [V0.0.2] categories (R-108)
  render_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(render_json)),
  max_hops INTEGER NOT NULL DEFAULT 2 CHECK (max_hops BETWEEN 1 AND 8),
  priority INTEGER NOT NULL DEFAULT 100,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE binding_input (
  binding_id TEXT NOT NULL REFERENCES binding(id) ON DELETE CASCADE,
  selector TEXT NOT NULL,                      -- profile:<id> | tag:<t> | sv:<cfg> | sched:<id> | content:<src> | *
  alias TEXT,
  PRIMARY KEY (binding_id, selector)
);
CREATE TABLE binding_output (
  binding_id TEXT NOT NULL REFERENCES binding(id) ON DELETE CASCADE,
  account_id TEXT NOT NULL REFERENCES channel_account(id),
  peer_selector TEXT NOT NULL DEFAULT 'owner', -- owner | peer:<id> | group:<id> | sub:<group_id>
  role TEXT NOT NULL DEFAULT 'primary' CHECK (role IN ('primary','fallback','cc')),
  min_prio TEXT NOT NULL DEFAULT 'p3' CHECK (min_prio IN ('p0','p1','p2','p3')),
  PRIMARY KEY (binding_id, account_id, peer_selector)
);

-- ===== 会话 =====
CREATE TABLE fleet_session (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES agent_profile(id),
  agent_session_id TEXT,                       -- resume ID（Agent 命名空间）
  account_id TEXT REFERENCES channel_account(id),
  peer_id TEXT,
  binding_id TEXT REFERENCES binding(id),
  cwd TEXT, title TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','idle','closed','failed')),
  generation INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL, last_active_at TEXT NOT NULL
);
CREATE INDEX ix_fs_agent ON fleet_session(profile_id, agent_session_id);
CREATE INDEX ix_fs_peer ON fleet_session(account_id, peer_id, status);
CREATE TABLE session_lineage (
  from_session_id TEXT NOT NULL REFERENCES fleet_session(id),
  to_session_id TEXT NOT NULL REFERENCES fleet_session(id),
  reason TEXT NOT NULL CHECK (reason IN ('clear','resume','fork','import')),
  at TEXT NOT NULL, PRIMARY KEY (from_session_id, to_session_id)
);
CREATE TABLE reply_cursor (
  account_id TEXT NOT NULL, peer_id TEXT NOT NULL, binding_id TEXT NOT NULL REFERENCES binding(id) ON DELETE CASCADE,
  current_session_id TEXT REFERENCES fleet_session(id),
  pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0,1)), updated_at TEXT NOT NULL,
  PRIMARY KEY (account_id, peer_id, binding_id)
);
-- [V0.0.2] 会话互斥 turn 队列（R-208 “已排队第 N 位”；持久化队列四原则）
CREATE TABLE turn_queue (
  id TEXT PRIMARY KEY,
  fleet_session_id TEXT NOT NULL REFERENCES fleet_session(id),
  envelope_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','done','cancelled','failed')),
  position INTEGER NOT NULL,                   -- 可见：回执“排队第 N 位”
  enqueued_at TEXT NOT NULL, started_at TEXT, ended_at TEXT
);
CREATE UNIQUE INDEX ux_turn_running ON turn_queue(fleet_session_id) WHERE status='running';   -- 同会话同时最多 1 个 turn
CREATE INDEX ix_turn_q ON turn_queue(fleet_session_id, status, position);

-- ===== 事件库（两端记录唯一事实来源）=====
CREATE TABLE event (
  id TEXT PRIMARY KEY,
  fleet_session_id TEXT REFERENCES fleet_session(id),
  turn_id TEXT, dir TEXT NOT NULL CHECK (dir IN ('in','out')),
  kind TEXT NOT NULL, prio TEXT NOT NULL DEFAULT 'p2' CHECK (prio IN ('p0','p1','p2','p3')),
  category TEXT,                               -- [V0.0.2] 完成/失败/审批/进度/汇报… (R-108)
  src TEXT NOT NULL, dst_json TEXT CHECK (dst_json IS NULL OR json_valid(dst_json)),
  parts_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(parts_json)),
  text_digest TEXT,
  source TEXT NOT NULL DEFAULT 'live' CHECK (source IN ('live','import','replay')),
  dedupe_key TEXT, ts TEXT NOT NULL
);
CREATE INDEX ix_event_session ON event(fleet_session_id, id);
CREATE UNIQUE INDEX ux_event_dedupe ON event(dedupe_key) WHERE dedupe_key IS NOT NULL;
CREATE VIRTUAL TABLE event_fts USING fts5(text_digest, content='event', content_rowid='rowid', tokenize='trigram');
-- [V0.0.2] V0.0.1 DDL 缺少外部内容 FTS 同步触发器（存在缺陷，已补）
CREATE TRIGGER event_ai AFTER INSERT ON event BEGIN
  INSERT INTO event_fts(rowid, text_digest) VALUES (new.rowid, new.text_digest);
END;
CREATE TRIGGER event_ad AFTER DELETE ON event BEGIN
  INSERT INTO event_fts(event_fts, rowid, text_digest) VALUES ('delete', old.rowid, old.text_digest);
END;
CREATE TRIGGER event_au AFTER UPDATE OF text_digest ON event BEGIN
  INSERT INTO event_fts(event_fts, rowid, text_digest) VALUES ('delete', old.rowid, old.text_digest);
  INSERT INTO event_fts(rowid, text_digest) VALUES (new.rowid, new.text_digest);
END;

-- ===== 出站：Outbox / 限流 / 配额 =====
CREATE TABLE outbox (
  id TEXT PRIMARY KEY, envelope_id TEXT NOT NULL REFERENCES event(id),
  account_id TEXT NOT NULL REFERENCES channel_account(id), peer_id TEXT NOT NULL,
  prio TEXT NOT NULL CHECK (prio IN ('p0','p1','p2','p3')),
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','sending','sent','failed','expired','deferred','held','merged','cancelled')),  -- [V0.0.2] held/merged/cancelled
  hold_reason TEXT CHECK (hold_reason IS NULL OR hold_reason IN ('quota_exhausted','pending_gate','pending_permission','quiet_hours','merge_window')),  -- [V0.0.2] Orca held 规则在 IM 侧
  merged_into TEXT REFERENCES outbox(id),      -- [V0.0.2] p3 合并摘要
  attempts INTEGER NOT NULL DEFAULT 0, next_at TEXT NOT NULL, expires_at TEXT,
  error_class TEXT, platform_msg_id TEXT, dedupe_key TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  CHECK ((status='held') = (hold_reason IS NOT NULL))
);
CREATE INDEX ix_outbox_due ON outbox(status, next_at, prio);
CREATE UNIQUE INDEX ux_outbox_dedupe ON outbox(account_id, peer_id, dedupe_key) WHERE dedupe_key IS NOT NULL;
CREATE TABLE rate_bucket (
  scope TEXT PRIMARY KEY, capacity REAL NOT NULL, refill_per_s REAL NOT NULL,
  tokens REAL NOT NULL, frozen_until TEXT, updated_at TEXT NOT NULL
);
CREATE TABLE quota_state (
  account_id TEXT NOT NULL REFERENCES channel_account(id), peer_id TEXT NOT NULL,
  window_kind TEXT NOT NULL CHECK (window_kind IN ('inbound_window','daily','monthly')),
  window_start TEXT NOT NULL, window_end TEXT NOT NULL,
  remaining INTEGER NOT NULL CHECK (remaining >= 0), capacity INTEGER NOT NULL CHECK (capacity >= 0),
  reserved_p0 INTEGER NOT NULL DEFAULT 2,
  PRIMARY KEY (account_id, peer_id, window_kind)
);

-- ===== 审批 =====
CREATE TABLE permission (
  request_id TEXT PRIMARY KEY,
  fleet_session_id TEXT NOT NULL REFERENCES fleet_session(id),
  acp_request_id TEXT, tool_call_id TEXT, title TEXT,
  risk TEXT NOT NULL DEFAULT 'medium' CHECK (risk IN ('low','medium','high')),
  options_json TEXT NOT NULL CHECK (json_valid(options_json)),
  reply_token TEXT,                            -- 无按钮渠道 Y1/N
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','decided','expired','cancelled')),
  decision_option_id TEXT, decided_by TEXT, decided_via TEXT,
  expires_at TEXT NOT NULL, created_at TEXT NOT NULL, decided_at TEXT
);
CREATE INDEX ix_perm_pending ON permission(status, expires_at);
CREATE TABLE permission_rule (
  id TEXT PRIMARY KEY, profile_id TEXT REFERENCES agent_profile(id),
  tool_pattern TEXT NOT NULL, effect TEXT NOT NULL CHECK (effect IN ('allow','deny')),
  created_by TEXT NOT NULL, created_at TEXT NOT NULL
);

-- ===== 调度 =====
CREATE TABLE schedule (
  id TEXT PRIMARY KEY, name TEXT NOT NULL,
  rule_json TEXT NOT NULL CHECK (json_valid(rule_json)),
  timezone TEXT NOT NULL DEFAULT 'Asia/Shanghai',
  action_json TEXT NOT NULL CHECK (json_valid(action_json)),   -- prompt_agent|send_text|broadcast|sv_task|content_collect|digest_compose
  binding_id TEXT REFERENCES binding(id),
  concurrency TEXT NOT NULL DEFAULT 'skip_if_running' CHECK (concurrency IN ('skip_if_running','queue','parallel')),
  catch_up TEXT NOT NULL DEFAULT 'skip' CHECK (catch_up IN ('skip','run_once','run_all_capped')),
  calendar_degraded INTEGER NOT NULL DEFAULT 0 CHECK (calendar_degraded IN (0,1)),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)), next_run_at TEXT, last_run_at TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE INDEX ix_schedule_due ON schedule(enabled, next_run_at);
CREATE TABLE schedule_run (
  id TEXT PRIMARY KEY, schedule_id TEXT NOT NULL REFERENCES schedule(id),
  planned_at TEXT NOT NULL, started_at TEXT, ended_at TEXT,
  status TEXT NOT NULL CHECK (status IN ('fired','skipped','missed','succeeded','failed')),
  reason TEXT, UNIQUE(schedule_id, planned_at)
);
CREATE TABLE holiday_calendar (
  region TEXT NOT NULL DEFAULT 'CN', date TEXT NOT NULL,
  is_off_day INTEGER NOT NULL CHECK (is_off_day IN (0,1)),
  name TEXT, source TEXT NOT NULL CHECK (source IN ('holiday-cn','manual')),
  PRIMARY KEY (region, date)
);
CREATE TABLE holiday_year_status (
  region TEXT NOT NULL, year INTEGER NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('published','missing','manual')),
  source_url TEXT, synced_at TEXT, PRIMARY KEY (region, year)
);

-- ===== 通知模式：订阅与广播 =====
CREATE TABLE subscription_group (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT,
  join_policy TEXT NOT NULL DEFAULT 'opt_in' CHECK (join_policy IN ('opt_in','admin_only')),
  default_timezone TEXT NOT NULL DEFAULT 'Asia/Shanghai', created_at TEXT NOT NULL
);
CREATE TABLE subscription (
  id TEXT PRIMARY KEY, group_id TEXT NOT NULL REFERENCES subscription_group(id),
  account_id TEXT NOT NULL REFERENCES channel_account(id), peer_id TEXT NOT NULL,
  timezone TEXT, locale TEXT, prefs_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(prefs_json)),
  opted_in_at TEXT NOT NULL, opted_in_via TEXT NOT NULL,
  opted_out_at TEXT, UNIQUE(group_id, account_id, peer_id)
);
CREATE TABLE broadcast_job (
  id TEXT PRIMARY KEY, group_id TEXT NOT NULL REFERENCES subscription_group(id),
  schedule_run_id TEXT REFERENCES schedule_run(id),
  digest_id TEXT,                              -- [V0.0.2] → digest.id
  content_event_id TEXT REFERENCES event(id),
  status TEXT NOT NULL CHECK (status IN ('generating','reviewing','fanning_out','done','failed','cancelled')),
  total INTEGER NOT NULL DEFAULT 0, sent INTEGER NOT NULL DEFAULT 0, failed INTEGER NOT NULL DEFAULT 0,
  window_start TEXT, window_end TEXT, created_at TEXT NOT NULL
);
CREATE TABLE broadcast_delivery (
  job_id TEXT NOT NULL REFERENCES broadcast_job(id), subscription_id TEXT NOT NULL REFERENCES subscription(id),
  outbox_id TEXT REFERENCES outbox(id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','queued','sent','failed','skipped','blocked')),
  error_class TEXT, PRIMARY KEY (job_id, subscription_id)
);

-- ===== [V0.0.2] 内容流水线（S4，G31；借 BettaFish MindSpider 数据模型思路，clean-room）=====
CREATE TABLE content_source (
  id TEXT PRIMARY KEY, name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('rss','http_api','github_trending','agent','bettafish_report','manual')),
  config_json TEXT NOT NULL CHECK (json_valid(config_json)),
  terms_note TEXT,                             -- 来源条款/合规备注
  health TEXT NOT NULL DEFAULT 'ok' CHECK (health IN ('ok','degraded','down')),
  last_ok_at TEXT, enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1))
);
CREATE TABLE content_item (
  id TEXT PRIMARY KEY, source_id TEXT NOT NULL REFERENCES content_source(id),
  url TEXT, title TEXT NOT NULL, summary TEXT, tags_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(tags_json)),
  published_at TEXT, collected_at TEXT NOT NULL, content_hash TEXT NOT NULL,
  UNIQUE(content_hash)
);
CREATE TABLE digest (                           -- Fleet-IR 文档（G32），总控汇报 / S2 日报 / S4 资讯共用
  id TEXT PRIMARY KEY,
  purpose TEXT NOT NULL CHECK (purpose IN ('s4_daily','s2_daily','sv_report','meeting_minutes')),
  ir_version INTEGER NOT NULL DEFAULT 1,
  ir_json TEXT NOT NULL CHECK (json_valid(ir_json)),
  status TEXT NOT NULL CHECK (status IN ('draft','validated','approved','published','rejected')),
  validation_json TEXT CHECK (validation_json IS NULL OR json_valid(validation_json)),
  created_at TEXT NOT NULL, approved_by TEXT
);
CREATE TABLE digest_item (
  digest_id TEXT NOT NULL REFERENCES digest(id) ON DELETE CASCADE,
  content_item_id TEXT NOT NULL REFERENCES content_item(id),
  rank INTEGER NOT NULL, PRIMARY KEY (digest_id, content_item_id)
);

-- ===== 插件与审计 =====
CREATE TABLE plugin (
  name TEXT PRIMARY KEY, version TEXT NOT NULL, kind TEXT NOT NULL CHECK (kind IN ('input','channel','renderer','tool','content_source')),
  manifest_json TEXT NOT NULL CHECK (json_valid(manifest_json)), isolation TEXT NOT NULL DEFAULT 'inproc' CHECK (isolation IN ('inproc','subprocess')),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)), installed_at TEXT NOT NULL
);
CREATE TABLE audit_log (
  id TEXT PRIMARY KEY, ts TEXT NOT NULL, actor TEXT NOT NULL,
  action TEXT NOT NULL, target TEXT, detail_json TEXT CHECK (detail_json IS NULL OR json_valid(detail_json))
);

-- ===== 知识/记忆映射（Hindsight，可选）=====
CREATE TABLE memory_bank_link (
  scope TEXT NOT NULL CHECK (scope IN ('project','persona','supervisor')),
  scope_ref TEXT NOT NULL, bank_id TEXT NOT NULL, base_url TEXT NOT NULL,
  retain_policy_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(retain_policy_json)),
  mm_trigger_json TEXT NOT NULL DEFAULT '{"mode":"delta","refresh_after_consolidation":true,"full_refresh_cron":"0 3 * * 1"}' CHECK (json_valid(mm_trigger_json)),  -- [V0.0.2] Hindsight full_refresh_cron（与 refresh_cron 互斥）
  PRIMARY KEY (scope, scope_ref)
);
CREATE TABLE persona_revision (                 -- [V0.0.2] 画像版本 diff 审批（G22）
  id TEXT PRIMARY KEY, persona_ref TEXT NOT NULL, version INTEGER NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('delta','full_refresh','manual')),
  diff_json TEXT NOT NULL CHECK (json_valid(diff_json)),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  decided_by TEXT, created_at TEXT NOT NULL, decided_at TEXT,
  UNIQUE(persona_ref, version)
);

-- ===== 总控（Supervisor）=====
CREATE TABLE sv_config (
  id TEXT PRIMARY KEY, name TEXT NOT NULL,
  binding_id TEXT NOT NULL REFERENCES binding(id),
  brain_kind TEXT NOT NULL CHECK (brain_kind IN ('model','acp')),
  models_json TEXT NOT NULL CHECK (json_valid(models_json)),
  manager_profile_id TEXT REFERENCES agent_profile(id),
  meeting_json TEXT NOT NULL DEFAULT '{"rounds_max":2,"rounds_cap":4,"timeout_s":300,"max_participants":5,"host_policy":"on_round_complete","quorum":"all"}' CHECK (json_valid(meeting_json)),  -- [V0.0.2] host_policy/quorum
  budget_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(budget_json)),
  concurrency INTEGER NOT NULL DEFAULT 4 CHECK (concurrency BETWEEN 1 AND 32),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)), created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE sv_skill (
  id TEXT PRIMARY KEY, config_id TEXT NOT NULL REFERENCES sv_config(id),
  scope TEXT NOT NULL CHECK (scope IN ('manager','worker')),
  name TEXT NOT NULL, version INTEGER NOT NULL, path TEXT NOT NULL, sha256 TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, UNIQUE(config_id, name, version)
);
CREATE TABLE sv_policy (
  id TEXT PRIMARY KEY, config_id TEXT NOT NULL REFERENCES sv_config(id),
  category TEXT NOT NULL CHECK (category IN ('auto_reply','digest','decision','resource','risk','blocked')),
  match_json TEXT NOT NULL CHECK (json_valid(match_json)), action_json TEXT NOT NULL CHECK (json_valid(action_json)),
  priority INTEGER NOT NULL DEFAULT 100, enabled INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE sv_worker (
  config_id TEXT NOT NULL REFERENCES sv_config(id), profile_id TEXT NOT NULL REFERENCES agent_profile(id),
  persona TEXT, skills_json TEXT NOT NULL DEFAULT '[]', max_parallel INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (config_id, profile_id)
);
CREATE TABLE sv_run (
  id TEXT PRIMARY KEY, config_id TEXT NOT NULL REFERENCES sv_config(id),
  objective TEXT NOT NULL, origin TEXT NOT NULL,
  kernel_goal_id TEXT,
  phase TEXT NOT NULL CHECK (phase IN ('intake','clarify','meeting','decide','plan','execute','report','done','cancelled','failed','paused')),
  budget_used_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE sv_meeting (
  id TEXT PRIMARY KEY, run_id TEXT NOT NULL REFERENCES sv_run(id),
  agenda_json TEXT NOT NULL CHECK (json_valid(agenda_json)), participants_json TEXT NOT NULL CHECK (json_valid(participants_json)),
  host_policy TEXT NOT NULL DEFAULT 'on_round_complete' CHECK (host_policy IN ('on_round_complete','every_n_turns','on_conflict')),  -- [V0.0.2] BettaFish 阈值触发的改造
  round INTEGER NOT NULL DEFAULT 0, rounds_max INTEGER NOT NULL DEFAULT 2 CHECK (rounds_max BETWEEN 1 AND 4),
  status TEXT NOT NULL CHECK (status IN ('open','round_running','collecting','synthesizing','deciding','closed','aborted')),
  divergence_json TEXT, decision_json TEXT, minutes_digest_id TEXT REFERENCES digest(id),
  created_at TEXT NOT NULL, closed_at TEXT
);
CREATE TABLE sv_meeting_turn (
  meeting_id TEXT NOT NULL REFERENCES sv_meeting(id), round INTEGER NOT NULL, profile_id TEXT NOT NULL,
  fleet_session_id TEXT REFERENCES fleet_session(id), persona TEXT,
  statement_json TEXT CHECK (statement_json IS NULL OR json_valid(statement_json)),
  status TEXT NOT NULL CHECK (status IN ('asked','answered','invalid','retrying','timeout','absent')),
  retries INTEGER NOT NULL DEFAULT 0 CHECK (retries BETWEEN 0 AND 1),
  tokens INTEGER, asked_at TEXT NOT NULL, answered_at TEXT,
  PRIMARY KEY (meeting_id, round, profile_id)
);
CREATE TABLE sv_meeting_event (                  -- [V0.0.2] 结构化会议事件（替代 BettaFish 日志总线），SSE 序号补发
  meeting_id TEXT NOT NULL REFERENCES sv_meeting(id), seq INTEGER NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('opened','round_started','statement','statement_invalid','timeout','round_complete','host_digest','divergence','decision','gate_opened','gate_resolved','dispatched','closed','aborted','side_note')),
  actor TEXT NOT NULL, payload_json TEXT NOT NULL CHECK (json_valid(payload_json)), ts TEXT NOT NULL,
  PRIMARY KEY (meeting_id, seq)
);
CREATE TABLE sv_dispatch (
  id TEXT PRIMARY KEY, run_id TEXT NOT NULL REFERENCES sv_run(id),
  kernel_todo_id TEXT NOT NULL, profile_id TEXT NOT NULL REFERENCES agent_profile(id), fleet_session_id TEXT REFERENCES fleet_session(id),
  status TEXT NOT NULL CHECK (status IN ('pending','dispatched','working','asked','done','failed','stale','circuit_broken')),
  failure_count INTEGER NOT NULL DEFAULT 0, last_heartbeat_at TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE sv_message (
  id INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT REFERENCES sv_run(id),
  from_handle TEXT NOT NULL, to_handle TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('status','dispatch','worker_done','question','answer','escalation','decision_gate','handoff','heartbeat','report','side_chat','meeting_ask','meeting_digest')),
  priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('normal','high','urgent')),
  thread_id TEXT, subject TEXT, body TEXT, payload_json TEXT CHECK (payload_json IS NULL OR json_valid(payload_json)),
  held INTEGER NOT NULL DEFAULT 0 CHECK (held IN (0,1)),                 -- [V0.0.2] Orca held：员工有待答权限时暂不投递
  held_reason TEXT CHECK (held_reason IS NULL OR held_reason IN ('pending_permission','turn_running','paused')),
  read INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, delivered_at TEXT,
  CHECK ((held=1) = (held_reason IS NOT NULL))
);
CREATE INDEX ix_sv_inbox ON sv_message(to_handle, read, held);
CREATE TABLE sv_gate (
  id TEXT PRIMARY KEY, run_id TEXT NOT NULL REFERENCES sv_run(id), kernel_todo_id TEXT,
  category TEXT NOT NULL CHECK (category IN ('decision','resource','risk','blocked','clarify')),
  question TEXT NOT NULL, options_json TEXT NOT NULL CHECK (json_valid(options_json)), recommendation TEXT, gate_reason TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending','resolved','timeout','cancelled')),
  resolution TEXT, resolved_by TEXT, outbox_id TEXT REFERENCES outbox(id),
  created_at TEXT NOT NULL, resolved_at TEXT
);
CREATE TABLE sv_review (
  id TEXT PRIMARY KEY, run_id TEXT NOT NULL REFERENCES sv_run(id), source_event_id TEXT NOT NULL,
  category TEXT NOT NULL, decided_by TEXT NOT NULL CHECK (decided_by IN ('rule','model','human')),
  policy_id TEXT REFERENCES sv_policy(id), rationale TEXT, created_at TEXT NOT NULL
);
CREATE TABLE sv_side_session (
  id TEXT PRIMARY KEY, config_id TEXT NOT NULL REFERENCES sv_config(id), account_id TEXT, peer_id TEXT,
  fleet_session_id TEXT REFERENCES fleet_session(id), created_at TEXT NOT NULL, last_active_at TEXT NOT NULL
);
CREATE TABLE sv_worker_stats (
  profile_id TEXT NOT NULL, role TEXT NOT NULL, done INTEGER NOT NULL DEFAULT 0, failed INTEGER NOT NULL DEFAULT 0,
  avg_minutes REAL, updated_at TEXT NOT NULL, PRIMARY KEY (profile_id, role)
);

INSERT INTO schema_version(version, applied_at, note) VALUES (2, '2026-10-17T00:00:00Z', 'V0.0.2 design draft');
