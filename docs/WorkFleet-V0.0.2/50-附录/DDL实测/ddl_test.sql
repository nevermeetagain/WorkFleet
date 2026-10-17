.bail off
.headers off
PRAGMA foreign_keys=ON;
SELECT 'tables', count(*) FROM sqlite_master WHERE type='table';
SELECT 'indexes', count(*) FROM sqlite_master WHERE type='index';
SELECT 'triggers', count(*) FROM sqlite_master WHERE type='trigger';
INSERT INTO device VALUES('dev1','mbp','macos','edge',NULL,'2026-10-17T00:00:00Z');
INSERT INTO agent_profile(id,name,family,protocol,kind,device_id,launch_json,created_at,updated_at) VALUES('p-claude-a','claude-a','acp','acp-v1','claude','dev1','{"cmd":"npx","args":["@agentclientprotocol/claude-agent-acp@0.93.0"],"pin_version":"0.93.0"}','t','t');
INSERT INTO agent_profile(id,name,family,protocol,kind,created_at,updated_at) VALUES('p-codex-a','codex-a','acp','acp-v1','codex','t','t');
-- T1 JSON CHECK 应失败
INSERT INTO agent_profile(id,name,family,kind,launch_json,created_at,updated_at) VALUES('bad','bad','acp','x','{not json','t','t');
-- T2 family 枚举应失败
INSERT INTO agent_profile(id,name,family,kind,created_at,updated_at) VALUES('bad2','bad2','grpc','x','t','t');
INSERT INTO channel_account(id,adapter,credential_fingerprint,owner_peer_id,created_at,updated_at) VALUES('wechat:me','wechat-ilink','fp1','u1','t','t');
-- T3 同凭证第二个账号应失败（单例池键，R-309）
INSERT INTO channel_account(id,adapter,credential_fingerprint,created_at,updated_at) VALUES('wechat:dup','wechat-ilink','fp1','t','t');
INSERT INTO binding(id,name,mode,created_at,updated_at) VALUES('mgmt','mgmt-wechat','management','t','t');
INSERT INTO binding_input VALUES('mgmt','tag:all',NULL);
INSERT INTO binding_output VALUES('mgmt','wechat:me','owner','primary','p3');
-- T4 外键：不存在的账号应失败
INSERT INTO binding_output VALUES('mgmt','nope','owner','primary','p3');
INSERT INTO fleet_session(id,profile_id,agent_session_id,account_id,peer_id,binding_id,status,created_at,last_active_at) VALUES('F1','p-claude-a','9f3c','wechat:me','u1','mgmt','active','t','t');
-- T5 turn_queue：同会话第二个 running 应失败
INSERT INTO turn_queue VALUES('q1','F1','e1','running',0,'t',NULL,NULL);
INSERT INTO turn_queue VALUES('q2','F1','e2','queued',1,'t',NULL,NULL);
UPDATE turn_queue SET status='running' WHERE id='q2';
-- T6 事件 + FTS 触发器（中文 trigram）
INSERT INTO event(id,fleet_session_id,dir,kind,src,text_digest,ts) VALUES('E1','F1','out','msg.final','acp:claude','修复登录超时问题，测试 42/42 通过','t');
INSERT INTO event(id,fleet_session_id,dir,kind,src,text_digest,ts) VALUES('E2','F1','in','msg.text','wechat:me','随时对话不影响执行','t');
SELECT 'fts 登录超时', count(*) FROM event_fts WHERE event_fts MATCH '登录超时';
SELECT 'fts 随时对', count(*) FROM event_fts WHERE event_fts MATCH '随时对';
UPDATE event SET text_digest='已改为深色主题' WHERE id='E2';
SELECT 'fts after update 随时对', count(*) FROM event_fts WHERE event_fts MATCH '随时对';
SELECT 'fts after update 深色主题', count(*) FROM event_fts WHERE event_fts MATCH '深色主题';
-- T7 dedupe 部分唯一索引
INSERT INTO event(id,dir,kind,src,dedupe_key,ts) VALUES('E3','in','msg.text','x','d1','t');
INSERT INTO event(id,dir,kind,src,dedupe_key,ts) VALUES('E4','in','msg.text','x','d1','t');
-- T8 outbox held 一致性 CHECK：held 无原因应失败；带原因成功
INSERT INTO outbox(id,envelope_id,account_id,peer_id,prio,status,next_at,created_at,updated_at) VALUES('o1','E1','wechat:me','u1','p3','held','t','t','t');
INSERT INTO outbox(id,envelope_id,account_id,peer_id,prio,status,hold_reason,next_at,created_at,updated_at) VALUES('o2','E1','wechat:me','u1','p3','held','quota_exhausted','t','t','t');
-- T9 quota remaining 不得为负
INSERT INTO quota_state VALUES('wechat:me','u1','inbound_window','t0','t1',-1,10,2);
INSERT INTO quota_state VALUES('wechat:me','u1','inbound_window','t0','t1',10,10,2);
-- T10 总控：会议 rounds_max 上限 4
INSERT INTO sv_config(id,name,binding_id,brain_kind,models_json,created_at,updated_at) VALUES('sv1','main','mgmt','model','{"manager":{"model":"x"}}','t','t');
INSERT INTO sv_run(id,config_id,objective,origin,phase,created_at,updated_at) VALUES('r1','sv1','统一接入新登录','im:wechat:me:u1','meeting','t','t');
INSERT INTO sv_meeting(id,run_id,agenda_json,participants_json,rounds_max,status,created_at) VALUES('m-bad','r1','{}','[]',5,'open','t');
INSERT INTO sv_meeting(id,run_id,agenda_json,participants_json,rounds_max,status,created_at) VALUES('m1','r1','{}','["p-claude-a","p-codex-a"]',2,'open','t');
INSERT INTO sv_meeting_turn(meeting_id,round,profile_id,status,retries,asked_at) VALUES('m1',1,'p-claude-a','asked',0,'t');
INSERT INTO sv_meeting_turn(meeting_id,round,profile_id,status,retries,asked_at) VALUES('m1',1,'p-codex-a','retrying',2,'t');
INSERT INTO sv_meeting_event VALUES('m1',1,'opened','mgr','{}','t'),('m1',2,'round_started','mgr','{"round":1}','t');
INSERT INTO sv_meeting_event VALUES('m1',2,'statement','x','{}','t');
-- T11 sv_message held 一致性
INSERT INTO sv_message(run_id,from_handle,to_handle,type,held,held_reason,created_at) VALUES('r1','mgr','worker:p-codex-a','dispatch',1,'pending_permission','t');
INSERT INTO sv_message(run_id,from_handle,to_handle,type,held,created_at) VALUES('r1','mgr','worker:p-codex-a','dispatch',1,'t');
-- T12 memory_bank_link 默认 MM 触发器
INSERT INTO memory_bank_link(scope,scope_ref,bank_id,base_url) VALUES('persona','aidean','persona:aidean','http://127.0.0.1:3180');
SELECT 'mm_trigger', json_extract(mm_trigger_json,'$.full_refresh_cron') FROM memory_bank_link;
-- T13 内容去重
INSERT INTO content_source(id,name,kind,config_json) VALUES('s1','rss-a','rss','{"url":"https://example.invalid/feed"}');
INSERT INTO content_item(id,source_id,title,collected_at,content_hash) VALUES('c1','s1','A','t','h1');
INSERT INTO content_item(id,source_id,title,collected_at,content_hash) VALUES('c2','s1','A dup','t','h1');
-- 汇总
SELECT 'rows agent_profile', count(*) FROM agent_profile;
SELECT 'rows channel_account', count(*) FROM channel_account;
SELECT 'rows turn_running', count(*) FROM turn_queue WHERE status='running';
SELECT 'rows outbox', count(*) FROM outbox;
SELECT 'rows sv_meeting', count(*) FROM sv_meeting;
SELECT 'rows sv_meeting_turn', count(*) FROM sv_meeting_turn;
SELECT 'rows sv_meeting_event', count(*) FROM sv_meeting_event;
SELECT 'rows sv_message', count(*) FROM sv_message;
SELECT 'rows content_item', count(*) FROM content_item;
PRAGMA foreign_key_check;
PRAGMA integrity_check;
