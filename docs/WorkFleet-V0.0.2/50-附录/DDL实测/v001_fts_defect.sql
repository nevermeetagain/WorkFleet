CREATE TABLE event (id TEXT PRIMARY KEY, text_digest TEXT, ts TEXT NOT NULL);
CREATE VIRTUAL TABLE event_fts USING fts5(text_digest, content='event', content_rowid='rowid', tokenize='trigram');
INSERT INTO event VALUES('E1','修复登录超时问题','t');
SELECT 'V0.0.1 DDL（无触发器）命中数', count(*) FROM event_fts WHERE event_fts MATCH '登录超时';
